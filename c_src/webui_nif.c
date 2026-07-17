/*
  Elixir-WebUI NIF shim
  https://webui.me
  https://github.com/webui-dev/elixir-webui
  Licensed under MIT License.

  This translates the WebUI C API into NIFs. Two things here are load-bearing
  and easy to break by accident:

  1. WebUI fires bound-element callbacks on its own threads, which are not BEAM
     scheduler threads and so cannot run Elixir. `dispatch_event` therefore only
     does `enif_send` (legal from a non-scheduler thread with a process
     independent env) and returns immediately. WebUI is configured with
     `asynchronous_response` so it blocks that thread until Elixir answers via
     `interface_set_response`. See WebUI.Dispatcher for the other half.

  2. Anything that can block -- wait, show, script -- is scheduled on a dirty IO
     scheduler. On a normal scheduler these would stall the VM.
*/

// webui.h declares its API `__declspec(dllexport)` under MSVC unless told
// otherwise. We link WebUI statically, so we want plain externs -- exporting
// WebUI's symbols from our NIF would be wrong. The header guards on this.
#define WEBUI_EXPORT extern

#include "webui.h"
#include <erl_nif.h>
#include <string.h>

// -- Atoms ---------------------------------------

// Atom terms are immediates and stay valid in any environment, so caching them
// at load time is safe -- unlike every other term type.
static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_true;
static ERL_NIF_TERM atom_false;
static ERL_NIF_TERM atom_webui_event;

// -- Dispatcher registration ---------------------

static ErlNifPid dispatcher_pid;
static int dispatcher_set = 0;
static ErlNifMutex* dispatcher_lock = NULL;

// -- Helpers -------------------------------------

static ERL_NIF_TERM mk_bool(int v) { return v ? atom_true : atom_false; }

// Copy an Elixir binary into a NUL-terminated C string. Caller frees with
// enif_free. Returns NULL if the term is not a binary.
static char* cstr_of(ErlNifEnv* env, ERL_NIF_TERM term) {
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, term, &bin)) return NULL;
    char* out = (char*)enif_alloc(bin.size + 1);
    if (out == NULL) return NULL;
    if (bin.size > 0) memcpy(out, bin.data, bin.size);
    out[bin.size] = '\0';
    return out;
}

// Build an Elixir binary from a C string. A NULL string becomes <<>>.
static ERL_NIF_TERM bin_of(ErlNifEnv* env, const char* s) {
    ERL_NIF_TERM term;
    if (s == NULL) {
        enif_make_new_binary(env, 0, &term);
        return term;
    }
    size_t len = strlen(s);
    unsigned char* buf = enif_make_new_binary(env, len, &term);
    if (len > 0) memcpy(buf, s, len);
    return term;
}

static int get_size(ErlNifEnv* env, ERL_NIF_TERM term, size_t* out) {
    ErlNifUInt64 v;
    if (!enif_get_uint64(env, term, &v)) return 0;
    *out = (size_t)v;
    return 1;
}

static int get_bool(ErlNifEnv* env, ERL_NIF_TERM term, bool* out) {
    char buf[8];
    if (!enif_get_atom(env, term, buf, sizeof(buf), ERL_NIF_LATIN1)) return 0;
    if (strcmp(buf, "true") == 0) { *out = true; return 1; }
    if (strcmp(buf, "false") == 0) { *out = false; return 1; }
    return 0;
}

// -- Event dispatch ------------------------------

// Runs on a WebUI thread. Must not block and must not touch any ErlNifEnv
// belonging to a scheduler. If nothing is registered to handle the event we
// answer immediately ourselves, otherwise WebUI would wait forever.
static void dispatch_event(size_t window, size_t event_type, char* element,
                           size_t event_number, size_t bind_id) {
    ErlNifPid pid;
    int have_pid = 0;

    enif_mutex_lock(dispatcher_lock);
    if (dispatcher_set) {
        pid = dispatcher_pid;
        have_pid = 1;
    }
    enif_mutex_unlock(dispatcher_lock);

    if (!have_pid) {
        webui_interface_set_response(window, event_number, "");
        return;
    }

    ErlNifEnv* msg_env = enif_alloc_env();
    ERL_NIF_TERM msg = enif_make_tuple6(
        msg_env,
        atom_webui_event,
        enif_make_uint64(msg_env, window),
        enif_make_uint64(msg_env, event_type),
        bin_of(msg_env, element),
        enif_make_uint64(msg_env, event_number),
        enif_make_uint64(msg_env, bind_id));

    // A failed send means the dispatcher died. Answer on its behalf so the
    // WebUI thread is not stuck holding an unanswerable event.
    if (!enif_send(NULL, &pid, msg_env, msg)) {
        webui_interface_set_response(window, event_number, "");
    }

    enif_free_env(msg_env);
}

static ERL_NIF_TERM nif_set_dispatcher(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifPid pid;
    if (!enif_get_local_pid(env, argv[0], &pid)) return enif_make_badarg(env);

    enif_mutex_lock(dispatcher_lock);
    dispatcher_pid = pid;
    dispatcher_set = 1;
    enif_mutex_unlock(dispatcher_lock);

    return atom_ok;
}

// -- Window creation -----------------------------

static ERL_NIF_TERM nif_new_window(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_uint64(env, webui_new_window());
}

static ERL_NIF_TERM nif_new_window_id(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t n;
    if (!get_size(env, argv[0], &n)) return enif_make_badarg(env);
    return enif_make_uint64(env, webui_new_window_id(n));
}

static ERL_NIF_TERM nif_get_new_window_id(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_uint64(env, webui_get_new_window_id());
}

// -- Bind ----------------------------------------

static ERL_NIF_TERM nif_bind(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* element = cstr_of(env, argv[1]);
    if (element == NULL) return enif_make_badarg(env);

    size_t bind_id = webui_interface_bind(window, element, dispatch_event);
    enif_free(element);
    return enif_make_uint64(env, bind_id);
}

static ERL_NIF_TERM nif_set_response(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    char* response = cstr_of(env, argv[2]);
    if (response == NULL) return enif_make_badarg(env);

    webui_interface_set_response(window, event_number, response);
    enif_free(response);
    return atom_ok;
}

// -- Event arguments -----------------------------

#define EVENT_GETTER(name, cfun, mkterm)                                        \
    static ERL_NIF_TERM name(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) { \
        size_t window, event_number, index;                                     \
        if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);     \
        if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env); \
        if (!get_size(env, argv[2], &index)) return enif_make_badarg(env);      \
        return mkterm(env, cfun(window, event_number, index));                  \
    }

EVENT_GETTER(nif_get_string_at, webui_interface_get_string_at, bin_of)
EVENT_GETTER(nif_get_int_at, webui_interface_get_int_at, enif_make_int64)
EVENT_GETTER(nif_get_float_at, webui_interface_get_float_at, enif_make_double)
EVENT_GETTER(nif_get_size_at, webui_interface_get_size_at, enif_make_uint64)

static ERL_NIF_TERM nif_get_bool_at(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number, index;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    if (!get_size(env, argv[2], &index)) return enif_make_badarg(env);
    return mk_bool(webui_interface_get_bool_at(window, event_number, index));
}

// Raw argument bytes. get_string_at stops at the first NUL, so binary payloads
// need the explicit size from get_size_at.
static ERL_NIF_TERM nif_get_raw_at(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number, index;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    if (!get_size(env, argv[2], &index)) return enif_make_badarg(env);

    size_t len = webui_interface_get_size_at(window, event_number, index);
    const char* src = webui_interface_get_string_at(window, event_number, index);

    ERL_NIF_TERM term;
    unsigned char* buf = enif_make_new_binary(env, len, &term);
    if (src != NULL && len > 0) memcpy(buf, src, len);
    return term;
}

// -- Per-client operations -----------------------

static ERL_NIF_TERM nif_show_client(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    char* content = cstr_of(env, argv[2]);
    if (content == NULL) return enif_make_badarg(env);

    bool ok = webui_interface_show_client(window, event_number, content);
    enif_free(content);
    return mk_bool(ok);
}

static ERL_NIF_TERM nif_close_client(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    webui_interface_close_client(window, event_number);
    return atom_ok;
}

static ERL_NIF_TERM nif_navigate_client(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    char* url = cstr_of(env, argv[2]);
    if (url == NULL) return enif_make_badarg(env);

    webui_interface_navigate_client(window, event_number, url);
    enif_free(url);
    return atom_ok;
}

static ERL_NIF_TERM nif_run_client(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    char* script = cstr_of(env, argv[2]);
    if (script == NULL) return enif_make_badarg(env);

    webui_interface_run_client(window, event_number, script);
    enif_free(script);
    return atom_ok;
}

static ERL_NIF_TERM nif_send_raw_client(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, event_number;
    ErlNifBinary raw;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &event_number)) return enif_make_badarg(env);
    char* function = cstr_of(env, argv[2]);
    if (function == NULL) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &raw)) {
        enif_free(function);
        return enif_make_badarg(env);
    }

    webui_interface_send_raw_client(window, event_number, function, raw.data, raw.size);
    enif_free(function);
    return atom_ok;
}

// -- Show / server (dirty: may wait for the browser to connect) --

static ERL_NIF_TERM nif_show(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* content = cstr_of(env, argv[1]);
    if (content == NULL) return enif_make_badarg(env);

    bool ok = webui_show(window, content);
    enif_free(content);
    return mk_bool(ok);
}

static ERL_NIF_TERM nif_show_browser(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, browser;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* content = cstr_of(env, argv[1]);
    if (content == NULL) return enif_make_badarg(env);
    if (!get_size(env, argv[2], &browser)) {
        enif_free(content);
        return enif_make_badarg(env);
    }

    bool ok = webui_show_browser(window, content, browser);
    enif_free(content);
    return mk_bool(ok);
}

static ERL_NIF_TERM nif_show_wv(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* content = cstr_of(env, argv[1]);
    if (content == NULL) return enif_make_badarg(env);

    bool ok = webui_show_wv(window, content);
    enif_free(content);
    return mk_bool(ok);
}

static ERL_NIF_TERM nif_start_server(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* content = cstr_of(env, argv[1]);
    if (content == NULL) return enif_make_badarg(env);

    const char* url = webui_start_server(window, content);
    enif_free(content);
    return bin_of(env, url);
}

// -- Lifecycle -----------------------------------

// Dirty IO: blocks until every window closes.
static ERL_NIF_TERM nif_wait(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    webui_wait();
    return atom_ok;
}

static ERL_NIF_TERM nif_is_app_running(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return mk_bool(webui_interface_is_app_running());
}

#define WINDOW_VOID_NIF(name, cfun)                                             \
    static ERL_NIF_TERM name(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) { \
        size_t window;                                                          \
        if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);     \
        cfun(window);                                                           \
        return atom_ok;                                                         \
    }

WINDOW_VOID_NIF(nif_close, webui_close)
WINDOW_VOID_NIF(nif_destroy, webui_destroy)
WINDOW_VOID_NIF(nif_minimize, webui_minimize)
WINDOW_VOID_NIF(nif_maximize, webui_maximize)
WINDOW_VOID_NIF(nif_focus, webui_focus)
WINDOW_VOID_NIF(nif_set_center, webui_set_center)
WINDOW_VOID_NIF(nif_delete_profile, webui_delete_profile)

static ERL_NIF_TERM nif_exit(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    webui_exit();
    return atom_ok;
}

static ERL_NIF_TERM nif_clean(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    webui_clean();
    return atom_ok;
}

static ERL_NIF_TERM nif_delete_all_profiles(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    webui_delete_all_profiles();
    return atom_ok;
}

static ERL_NIF_TERM nif_is_shown(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    return mk_bool(webui_is_shown(window));
}

// -- Window flags --------------------------------

#define WINDOW_BOOL_NIF(name, cfun)                                             \
    static ERL_NIF_TERM name(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) { \
        size_t window;                                                          \
        bool status;                                                            \
        if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);     \
        if (!get_bool(env, argv[1], &status)) return enif_make_badarg(env);     \
        cfun(window, status);                                                   \
        return atom_ok;                                                         \
    }

WINDOW_BOOL_NIF(nif_set_kiosk, webui_set_kiosk)
WINDOW_BOOL_NIF(nif_set_resizable, webui_set_resizable)
WINDOW_BOOL_NIF(nif_set_hide, webui_set_hide)
WINDOW_BOOL_NIF(nif_set_public, webui_set_public)
WINDOW_BOOL_NIF(nif_set_frameless, webui_set_frameless)
WINDOW_BOOL_NIF(nif_set_transparent, webui_set_transparent)
WINDOW_BOOL_NIF(nif_set_high_contrast, webui_set_high_contrast)
WINDOW_BOOL_NIF(nif_set_event_blocking, webui_set_event_blocking)

static ERL_NIF_TERM nif_is_high_contrast(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return mk_bool(webui_is_high_contrast());
}

static ERL_NIF_TERM nif_browser_exist(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t browser;
    if (!get_size(env, argv[0], &browser)) return enif_make_badarg(env);
    return mk_bool(webui_browser_exist(browser));
}

static ERL_NIF_TERM nif_get_best_browser(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    return enif_make_uint64(env, webui_get_best_browser(window));
}

// -- Geometry ------------------------------------

#define WINDOW_2UINT_NIF(name, cfun)                                            \
    static ERL_NIF_TERM name(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) { \
        size_t window;                                                          \
        unsigned int a, b;                                                      \
        if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);     \
        if (!enif_get_uint(env, argv[1], &a)) return enif_make_badarg(env);     \
        if (!enif_get_uint(env, argv[2], &b)) return enif_make_badarg(env);     \
        cfun(window, a, b);                                                     \
        return atom_ok;                                                         \
    }

WINDOW_2UINT_NIF(nif_set_size, webui_set_size)
WINDOW_2UINT_NIF(nif_set_minimum_size, webui_set_minimum_size)
WINDOW_2UINT_NIF(nif_set_position, webui_set_position)

// -- Settings ------------------------------------

static ERL_NIF_TERM nif_set_config(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t option;
    bool status;
    if (!get_size(env, argv[0], &option)) return enif_make_badarg(env);
    if (!get_bool(env, argv[1], &status)) return enif_make_badarg(env);
    webui_set_config((webui_config)option, status);
    return atom_ok;
}

static ERL_NIF_TERM nif_set_timeout(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t seconds;
    if (!get_size(env, argv[0], &seconds)) return enif_make_badarg(env);
    webui_set_timeout(seconds);
    return atom_ok;
}

static ERL_NIF_TERM nif_set_runtime(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, runtime;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &runtime)) return enif_make_badarg(env);
    webui_set_runtime(window, runtime);
    return atom_ok;
}

static ERL_NIF_TERM nif_set_icon(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* icon = cstr_of(env, argv[1]);
    if (icon == NULL) return enif_make_badarg(env);
    char* type = cstr_of(env, argv[2]);
    if (type == NULL) {
        enif_free(icon);
        return enif_make_badarg(env);
    }

    webui_set_icon(window, icon, type);
    enif_free(icon);
    enif_free(type);
    return atom_ok;
}

static ERL_NIF_TERM nif_set_profile(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* name = cstr_of(env, argv[1]);
    if (name == NULL) return enif_make_badarg(env);
    char* path = cstr_of(env, argv[2]);
    if (path == NULL) {
        enif_free(name);
        return enif_make_badarg(env);
    }

    webui_set_profile(window, name, path);
    enif_free(name);
    enif_free(path);
    return atom_ok;
}

// Takes (window, string). `body` sees `window` and `s`, and owns freeing `s`.
#define WINDOW_STR_NIF(name, body)                                              \
    static ERL_NIF_TERM name(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) { \
        size_t window;                                                          \
        if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);     \
        char* s = cstr_of(env, argv[1]);                                        \
        if (s == NULL) return enif_make_badarg(env);                            \
        body                                                                    \
    }

WINDOW_STR_NIF(nif_set_proxy, {
    webui_set_proxy(window, s);
    enif_free(s);
    return atom_ok;
})

WINDOW_STR_NIF(nif_set_custom_parameters, {
    webui_set_custom_parameters(window, s);
    enif_free(s);
    return atom_ok;
})

WINDOW_STR_NIF(nif_navigate, {
    webui_navigate(window, s);
    enif_free(s);
    return atom_ok;
})

WINDOW_STR_NIF(nif_run, {
    webui_run(window, s);
    enif_free(s);
    return atom_ok;
})

WINDOW_STR_NIF(nif_set_root_folder, {
    bool ok = webui_set_root_folder(window, s);
    enif_free(s);
    return mk_bool(ok);
})

static ERL_NIF_TERM nif_set_default_root_folder(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char* path = cstr_of(env, argv[0]);
    if (path == NULL) return enif_make_badarg(env);
    bool ok = webui_set_default_root_folder(path);
    enif_free(path);
    return mk_bool(ok);
}

static ERL_NIF_TERM nif_set_browser_folder(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char* path = cstr_of(env, argv[0]);
    if (path == NULL) return enif_make_badarg(env);
    webui_set_browser_folder(path);
    enif_free(path);
    return atom_ok;
}

// -- JavaScript ----------------------------------

// Dirty IO: blocks until the browser answers or `timeout` elapses.
static ERL_NIF_TERM nif_script(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, timeout, buffer_len;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* script = cstr_of(env, argv[1]);
    if (script == NULL) return enif_make_badarg(env);
    if (!get_size(env, argv[2], &timeout) || !get_size(env, argv[3], &buffer_len)) {
        enif_free(script);
        return enif_make_badarg(env);
    }

    char* buffer = (char*)enif_alloc(buffer_len + 1);
    if (buffer == NULL) {
        enif_free(script);
        return enif_make_badarg(env);
    }
    memset(buffer, 0, buffer_len + 1);

    bool ok = webui_script(window, script, timeout, buffer, buffer_len);
    ERL_NIF_TERM result = enif_make_tuple2(env, ok ? atom_ok : atom_error, bin_of(env, buffer));

    enif_free(script);
    enif_free(buffer);
    return result;
}

static ERL_NIF_TERM nif_send_raw(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    ErlNifBinary raw;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    char* function = cstr_of(env, argv[1]);
    if (function == NULL) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &raw)) {
        enif_free(function);
        return enif_make_badarg(env);
    }

    webui_send_raw(window, function, raw.data, raw.size);
    enif_free(function);
    return atom_ok;
}

// -- URL / ports ---------------------------------

static ERL_NIF_TERM nif_get_url(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    return bin_of(env, webui_get_url(window));
}

static ERL_NIF_TERM nif_open_url(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char* url = cstr_of(env, argv[0]);
    if (url == NULL) return enif_make_badarg(env);
    webui_open_url(url);
    enif_free(url);
    return atom_ok;
}

static ERL_NIF_TERM nif_get_port(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    return enif_make_uint64(env, webui_get_port(window));
}

static ERL_NIF_TERM nif_set_port(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window, port;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    if (!get_size(env, argv[1], &port)) return enif_make_badarg(env);
    return mk_bool(webui_set_port(window, port));
}

static ERL_NIF_TERM nif_get_free_port(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_uint64(env, webui_get_free_port());
}

static ERL_NIF_TERM nif_get_parent_process_id(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    return enif_make_uint64(env, webui_get_parent_process_id(window));
}

static ERL_NIF_TERM nif_get_child_process_id(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    size_t window;
    if (!get_size(env, argv[0], &window)) return enif_make_badarg(env);
    return enif_make_uint64(env, webui_get_child_process_id(window));
}

// -- Utilities -----------------------------------

static ERL_NIF_TERM nif_get_mime_type(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char* file = cstr_of(env, argv[0]);
    if (file == NULL) return enif_make_badarg(env);
    ERL_NIF_TERM result = bin_of(env, webui_get_mime_type(file));
    enif_free(file);
    return result;
}

// webui_encode/webui_decode hand back a buffer owned by WebUI's allocator, so
// it must go back through webui_free rather than enif_free.
static ERL_NIF_TERM nif_encode(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char* str = cstr_of(env, argv[0]);
    if (str == NULL) return enif_make_badarg(env);
    char* out = webui_encode(str);
    ERL_NIF_TERM result = bin_of(env, out);
    enif_free(str);
    if (out != NULL) webui_free(out);
    return result;
}

static ERL_NIF_TERM nif_decode(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char* str = cstr_of(env, argv[0]);
    if (str == NULL) return enif_make_badarg(env);
    char* out = webui_decode(str);
    ERL_NIF_TERM result = bin_of(env, out);
    enif_free(str);
    if (out != NULL) webui_free(out);
    return result;
}

static ERL_NIF_TERM nif_get_last_error_number(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_uint64(env, webui_get_last_error_number());
}

static ERL_NIF_TERM nif_get_last_error_message(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return bin_of(env, webui_get_last_error_message());
}

static ERL_NIF_TERM nif_version(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return bin_of(env, WEBUI_VERSION);
}

// -- NIF lifecycle -------------------------------

static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");
    atom_true = enif_make_atom(env, "true");
    atom_false = enif_make_atom(env, "false");
    atom_webui_event = enif_make_atom(env, "webui_event");

    dispatcher_lock = enif_mutex_create("webui_dispatcher_lock");
    if (dispatcher_lock == NULL) return 1;

    // This is what makes the whole design work, and it must be set before any
    // window exists: it lets dispatch_event return without answering, so WebUI
    // waits for Elixir's set_response instead of taking the C callback's
    // return value.
    webui_set_config(asynchronous_response, true);

    // ui_event_blocking is deliberately left at its default of false, unlike
    // the Racket binding. Racket funnels every callback onto a single thread
    // regardless, so serializing costs it nothing. Here it would serialize
    // handlers that could otherwise run across schedulers, and it would
    // deadlock any handler calling webui_script -- that cannot answer until
    // the current event finishes, and the event cannot finish until the
    // handler does. Concurrent events are safe because set_response is keyed
    // by event_number rather than by arrival order.

    return 0;
}

static void unload(ErlNifEnv* env, void* priv_data) {
    if (dispatcher_lock != NULL) {
        enif_mutex_destroy(dispatcher_lock);
        dispatcher_lock = NULL;
    }
}

static ErlNifFunc nif_funcs[] = {
    // Dispatcher
    {"set_dispatcher", 1, nif_set_dispatcher},
    // Window creation
    {"new_window", 0, nif_new_window},
    {"new_window_id", 1, nif_new_window_id},
    {"get_new_window_id", 0, nif_get_new_window_id},
    // Bind / response
    {"bind", 2, nif_bind},
    {"set_response", 3, nif_set_response},
    // Event arguments
    {"get_string_at", 3, nif_get_string_at},
    {"get_int_at", 3, nif_get_int_at},
    {"get_float_at", 3, nif_get_float_at},
    {"get_bool_at", 3, nif_get_bool_at},
    {"get_size_at", 3, nif_get_size_at},
    {"get_raw_at", 3, nif_get_raw_at},
    // Per-client
    {"show_client", 3, nif_show_client, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"close_client", 2, nif_close_client},
    {"navigate_client", 3, nif_navigate_client},
    {"run_client", 3, nif_run_client},
    {"send_raw_client", 4, nif_send_raw_client},
    // Show / server
    {"show", 2, nif_show, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"show_browser", 3, nif_show_browser, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"show_wv", 2, nif_show_wv, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"start_server", 2, nif_start_server, ERL_NIF_DIRTY_JOB_IO_BOUND},
    // Lifecycle
    {"wait", 0, nif_wait, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"is_app_running", 0, nif_is_app_running},
    {"close", 1, nif_close},
    {"destroy", 1, nif_destroy},
    {"exit", 0, nif_exit},
    {"clean", 0, nif_clean},
    {"is_shown", 1, nif_is_shown},
    {"minimize", 1, nif_minimize},
    {"maximize", 1, nif_maximize},
    {"focus", 1, nif_focus},
    // Flags
    {"set_kiosk", 2, nif_set_kiosk},
    {"set_resizable", 2, nif_set_resizable},
    {"set_hide", 2, nif_set_hide},
    {"set_public", 2, nif_set_public},
    {"set_frameless", 2, nif_set_frameless},
    {"set_transparent", 2, nif_set_transparent},
    {"set_high_contrast", 2, nif_set_high_contrast},
    {"set_event_blocking", 2, nif_set_event_blocking},
    {"is_high_contrast", 0, nif_is_high_contrast},
    // Browser
    {"browser_exist", 1, nif_browser_exist},
    {"get_best_browser", 1, nif_get_best_browser},
    {"set_browser_folder", 1, nif_set_browser_folder},
    // Geometry
    {"set_size", 3, nif_set_size},
    {"set_minimum_size", 3, nif_set_minimum_size},
    {"set_position", 3, nif_set_position},
    {"set_center", 1, nif_set_center},
    // Settings
    {"set_config", 2, nif_set_config},
    {"set_timeout", 1, nif_set_timeout},
    {"set_runtime", 2, nif_set_runtime},
    {"set_icon", 3, nif_set_icon},
    {"set_profile", 3, nif_set_profile},
    {"set_proxy", 2, nif_set_proxy},
    {"set_custom_parameters", 2, nif_set_custom_parameters},
    {"set_root_folder", 2, nif_set_root_folder},
    {"set_default_root_folder", 1, nif_set_default_root_folder},
    {"delete_profile", 1, nif_delete_profile},
    {"delete_all_profiles", 0, nif_delete_all_profiles},
    // JavaScript
    {"run", 2, nif_run},
    {"script", 4, nif_script, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"send_raw", 3, nif_send_raw},
    // URL / ports / process
    {"navigate", 2, nif_navigate},
    {"get_url", 1, nif_get_url},
    {"open_url", 1, nif_open_url},
    {"get_port", 1, nif_get_port},
    {"set_port", 2, nif_set_port},
    {"get_free_port", 0, nif_get_free_port},
    {"get_parent_process_id", 1, nif_get_parent_process_id},
    {"get_child_process_id", 1, nif_get_child_process_id},
    // Utilities
    {"get_mime_type", 1, nif_get_mime_type},
    {"encode", 1, nif_encode},
    {"decode", 1, nif_decode},
    {"get_last_error_number", 0, nif_get_last_error_number},
    {"get_last_error_message", 0, nif_get_last_error_message},
    {"version", 0, nif_version}
};

ERL_NIF_INIT(Elixir.WebUI.Native, nif_funcs, load, NULL, NULL, unload)

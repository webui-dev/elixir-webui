defmodule WebUI do
  @moduledoc """
  Use any web browser or WebView as a GUI, with Elixir in the backend.

  This is the Elixir binding for [WebUI](https://webui.me). Rather than
  bundling a browser engine, WebUI drives one already installed on the machine
  and talks to it over a local WebSocket, so applications stay small and
  portable.

  ## Hello world

      win = WebUI.new_window()
      WebUI.show(win, "<html><script src=\\"webui.js\\"></script>Hi!</html>")
      WebUI.wait()
      WebUI.clean()

  ## Calling Elixir from JavaScript

  Any HTML you serve must load the bridge with `<script src="webui.js"></script>`.
  WebUI generates that file in memory -- it is not something you provide. Bound
  functions then appear in the page as async JS functions of the same name, and
  a handler's return value resolves the Promise:

      WebUI.bind(win, "add", fn e ->
        WebUI.Event.get_int(e, 0) + WebUI.Event.get_int(e, 1)
      end)

      # In the page:  add(2, 3).then(r => console.log(r))  //=> "5"

  Responses cross to JavaScript as strings. Numbers, booleans and atoms are
  converted for you; `nil` and `:ok` become `""`. To return structured data,
  encode it yourself and return the resulting string.

  Handlers run in supervised tasks, so blocking inside one is fine and a crash
  is contained -- it is logged, and the Promise resolves to `""`.

  ## Calling JavaScript from Elixir

  `run/2` fires and forgets; `script/3` waits for the result.

      WebUI.run(win, "document.title = 'Set from Elixir'")
      {:ok, "42"} = WebUI.script(win, "return 6 * 7;")

  ## Windows

  A window is just an integer handle from `new_window/0`, matching the other
  WebUI bindings. It is not a process and is not linked to one, so closing it
  is explicit: `close/1` shuts the window but keeps the object, `destroy/1`
  frees it, and `clean/1` releases WebUI's resources at the end.
  """

  alias WebUI.{Browser, Config, Dispatcher, Event, Native, Runtime}

  @type window :: non_neg_integer()

  # -- Window creation ---------------------------------------------------

  @doc "Create a new window and return its handle."
  @spec new_window() :: window()
  def new_window, do: Native.new_window()

  @doc "Create a new window using a specific number (`0 < number < 65535`)."
  @spec new_window(window()) :: window()
  def new_window(number), do: Native.new_window_id(number)

  @doc "Get the first unused window number, for use with `new_window/1`."
  @spec get_new_window_id() :: window()
  def get_new_window_id, do: Native.get_new_window_id()

  # -- Binding -----------------------------------------------------------

  @doc """
  Bind an HTML element or JavaScript function name to `fun`, returning the bind ID.

  `fun` receives a `WebUI.Event` and its return value resolves the JS Promise.
  Binding `""` catches every event on the window, which is how you observe
  `:connected` and `:disconnected`.

      WebUI.bind(win, "save", fn e -> save(WebUI.Event.get_string(e, 0)) end)

      WebUI.bind(win, "", fn
        %WebUI.Event{type: :connected} -> IO.puts("client connected")
        _ -> :ok
      end)
  """
  @spec bind(window(), binary(), (Event.t() -> term())) :: non_neg_integer()
  def bind(window, element, fun) when is_function(fun, 1),
    do: Dispatcher.bind(window, element, fun)

  # -- Show / serve ------------------------------------------------------

  @doc """
  Show `content` in the best available browser, returning whether it worked.

  `content` may be inline HTML, a path to a local file, a folder, or a URL.
  Pass `""` to serve the current root folder. If the window is already open it
  is refreshed instead.

  By default this waits for the browser to connect before returning; set
  `set_config(:show_wait_connection, false)` to return immediately.
  """
  @spec show(window(), binary()) :: boolean()
  def show(window, content \\ ""), do: Native.show(window, content)

  @doc "Like `show/2`, but with a specific `WebUI.Browser`."
  @spec show_browser(window(), binary(), Browser.t() | non_neg_integer()) :: boolean()
  def show_browser(window, content, browser),
    do: Native.show_browser(window, content, Browser.to_int(browser))

  @doc """
  Like `show/2`, but in a WebView window instead of a browser.

  > #### Not usable from Elixir on macOS {: .warning}
  >
  > WebView mode needs its event loop on the process's main thread, which on
  > the BEAM belongs to the VM and cannot be borrowed by a NIF. Windows and
  > Linux are unaffected. Use `show/2` for portable code.
  """
  @spec show_wv(window(), binary()) :: boolean()
  def show_wv(window, content \\ ""), do: Native.show_wv(window, content)

  @doc "Start only the local web server and return its URL. No window is opened."
  @spec start_server(window(), binary()) :: binary()
  def start_server(window, content \\ ""), do: Native.start_server(window, content)

  # -- Lifecycle ---------------------------------------------------------

  @doc """
  Block until every open window closes.

  Runs on a dirty scheduler, so it blocks only the calling process.
  """
  @spec wait() :: :ok
  def wait, do: Native.wait()

  @doc "Whether any window is still running."
  @spec app_running?() :: boolean()
  def app_running?, do: Native.is_app_running()

  @doc "Close `window` for all clients. The window object survives; see `destroy/1`."
  @spec close(window()) :: :ok
  def close(window), do: Native.close(window)

  @doc "Close `window`, free it, and drop its handlers."
  @spec destroy(window()) :: :ok
  def destroy(window) do
    :ok = Dispatcher.forget(window)
    Native.destroy(window)
  end

  @doc "Close all windows, causing `wait/0` to return."
  @spec exit() :: :ok
  def exit, do: Native.exit()

  @doc "Free WebUI's resources. Call once, after `wait/0`."
  @spec clean() :: :ok
  def clean, do: Native.clean()

  @doc "Whether `window` is currently shown."
  @spec shown?(window()) :: boolean()
  def shown?(window), do: Native.is_shown(window)

  @doc "Minimize a WebView window."
  @spec minimize(window()) :: :ok
  def minimize(window), do: Native.minimize(window)

  @doc "Maximize a WebView window."
  @spec maximize(window()) :: :ok
  def maximize(window), do: Native.maximize(window)

  @doc "Bring `window` to the front and focus it."
  @spec focus(window()) :: :ok
  def focus(window), do: Native.focus(window)

  # -- JavaScript --------------------------------------------------------

  @doc "Run JavaScript in every client of `window` without waiting for a result."
  @spec run(window(), binary()) :: :ok
  def run(window, script), do: Native.run(window, script)

  @doc """
  Run JavaScript and wait for the result. Single-client mode only.

  Returns `{:ok, result}`, or `{:error, message}` if the script raised or timed
  out. Note that `return` is required to get a value back.

  ## Options

    * `:timeout` - seconds to wait; `0` (default) waits forever.
    * `:buffer_size` - response buffer in bytes, default `8192`. Results
      longer than this are truncated, so raise it if you expect large payloads.

  ## Examples

      {:ok, "42"} = WebUI.script(win, "return 6 * 7;")
      {:ok, title} = WebUI.script(win, "return document.title;", timeout: 5)
  """
  @spec script(window(), binary(), keyword()) :: {:ok, binary()} | {:error, binary()}
  def script(window, script, opts \\ []) do
    Native.script(
      window,
      script,
      Keyword.get(opts, :timeout, 0),
      Keyword.get(opts, :buffer_size, 8192)
    )
  end

  @doc """
  Send raw bytes to a JavaScript function, which receives them as a `Uint8Array`.

      WebUI.send_raw(win, "receiveBytes", <<1, 2, 3>>)
  """
  @spec send_raw(window(), binary(), binary()) :: :ok
  def send_raw(window, function, raw), do: Native.send_raw(window, function, raw)

  @doc "Choose the runtime used for served `.js`/`.ts` files. See `WebUI.Runtime`."
  @spec set_runtime(window(), Runtime.t() | non_neg_integer()) :: :ok
  def set_runtime(window, runtime), do: Native.set_runtime(window, Runtime.to_int(runtime))

  # -- Navigation --------------------------------------------------------

  @doc "Navigate every client of `window` to `url`."
  @spec navigate(window(), binary()) :: :ok
  def navigate(window, url), do: Native.navigate(window, url)

  @doc "Current URL of a running window. Best called after `show/2`."
  @spec get_url(window()) :: binary()
  def get_url(window), do: Native.get_url(window)

  @doc "Open `url` in the system's default browser."
  @spec open_url(binary()) :: :ok
  def open_url(url), do: Native.open_url(url)

  # -- Files and folders -------------------------------------------------

  @doc "Set the web server root folder for `window`."
  @spec set_root_folder(window(), binary()) :: boolean()
  def set_root_folder(window, path), do: Native.set_root_folder(window, path)

  @doc "Set the web server root folder for all windows. Call before `show/2`."
  @spec set_default_root_folder(binary()) :: boolean()
  def set_default_root_folder(path), do: Native.set_default_root_folder(path)

  @doc "HTTP mime type for a filename."
  @spec get_mime_type(binary()) :: binary()
  def get_mime_type(file), do: Native.get_mime_type(file)

  # -- Appearance --------------------------------------------------------

  @doc "Set the window size in pixels."
  @spec set_size(window(), non_neg_integer(), non_neg_integer()) :: :ok
  def set_size(window, width, height), do: Native.set_size(window, width, height)

  @doc "Set the minimum window size in pixels."
  @spec set_minimum_size(window(), non_neg_integer(), non_neg_integer()) :: :ok
  def set_minimum_size(window, width, height), do: Native.set_minimum_size(window, width, height)

  @doc "Set the window position in pixels."
  @spec set_position(window(), non_neg_integer(), non_neg_integer()) :: :ok
  def set_position(window, x, y), do: Native.set_position(window, x, y)

  @doc "Center the window. Best called before `show/2`."
  @spec set_center(window()) :: :ok
  def set_center(window), do: Native.set_center(window)

  @doc "Set the favicon, e.g. `set_icon(win, \"<svg>...</svg>\", \"image/svg+xml\")`."
  @spec set_icon(window(), binary(), binary()) :: :ok
  def set_icon(window, icon, icon_type), do: Native.set_icon(window, icon, icon_type)

  @doc "Full-screen kiosk mode."
  @spec set_kiosk(window(), boolean()) :: :ok
  def set_kiosk(window, status), do: Native.set_kiosk(window, status)

  @doc "Whether a WebView window can be resized."
  @spec set_resizable(window(), boolean()) :: :ok
  def set_resizable(window, status), do: Native.set_resizable(window, status)

  @doc "Start the window hidden. Call before `show/2`."
  @spec set_hide(window(), boolean()) :: :ok
  def set_hide(window, status), do: Native.set_hide(window, status)

  @doc "Remove a WebView window's frame."
  @spec set_frameless(window(), boolean()) :: :ok
  def set_frameless(window, status), do: Native.set_frameless(window, status)

  @doc "Make a WebView window transparent."
  @spec set_transparent(window(), boolean()) :: :ok
  def set_transparent(window, status), do: Native.set_transparent(window, status)

  @doc "Enable high-contrast support, for theming with CSS."
  @spec set_high_contrast(window(), boolean()) :: :ok
  def set_high_contrast(window, status), do: Native.set_high_contrast(window, status)

  @doc "Whether the OS is using a high-contrast theme."
  @spec high_contrast?() :: boolean()
  def high_contrast?, do: Native.is_high_contrast()

  # -- Browser -----------------------------------------------------------

  @doc "The browser WebUI recommends for `window`. See `WebUI.Browser`."
  @spec get_best_browser(window()) :: Browser.t() | nil
  def get_best_browser(window), do: window |> Native.get_best_browser() |> Browser.from_int()

  @doc "Whether a browser is installed."
  @spec browser_exist(Browser.t() | non_neg_integer()) :: boolean()
  def browser_exist(browser), do: Native.browser_exist(Browser.to_int(browser))

  @doc "Set a custom browser folder path."
  @spec set_browser_folder(binary()) :: :ok
  def set_browser_folder(path), do: Native.set_browser_folder(path)

  @doc "Extra CLI parameters for the browser, e.g. `\"--remote-debugging-port=9222\"`."
  @spec set_custom_parameters(window(), binary()) :: :ok
  def set_custom_parameters(window, params), do: Native.set_custom_parameters(window, params)

  @doc "Set the browser profile. Empty name and path mean the default profile. Call before `show/2`."
  @spec set_profile(window(), binary(), binary()) :: :ok
  def set_profile(window, name \\ "", path \\ ""), do: Native.set_profile(window, name, path)

  @doc "Set a proxy server. Call before `show/2`."
  @spec set_proxy(window(), binary()) :: :ok
  def set_proxy(window, proxy_server), do: Native.set_proxy(window, proxy_server)

  @doc "Delete `window`'s local browser profile folder. Call after `wait/0`."
  @spec delete_profile(window()) :: :ok
  def delete_profile(window), do: Native.delete_profile(window)

  @doc "Delete all local browser profile folders. Call after `wait/0`."
  @spec delete_all_profiles() :: :ok
  def delete_all_profiles, do: Native.delete_all_profiles()

  # -- Network -----------------------------------------------------------

  @doc "Allow `window` to be reached from the public network."
  @spec set_public(window(), boolean()) :: :ok
  def set_public(window, status), do: Native.set_public(window, status)

  @doc "The network port `window` is running on."
  @spec get_port(window()) :: non_neg_integer()
  def get_port(window), do: Native.get_port(window)

  @doc "Pin `window` to a specific port. Returns whether the port was free."
  @spec set_port(window(), non_neg_integer()) :: boolean()
  def set_port(window, port), do: Native.set_port(window, port)

  @doc "Any free port on the system."
  @spec get_free_port() :: non_neg_integer()
  def get_free_port, do: Native.get_free_port()

  # -- Configuration -----------------------------------------------------

  @doc """
  Set a global behaviour flag. See `WebUI.Config` for the options.

  > #### Two options are load-bearing {: .warning}
  >
  > `:asynchronous_response` is set to `true` when the NIF loads and this
  > binding relies on it; setting it to `false` breaks every bound function.
  > `:ui_event_blocking` is left `false` so handlers run in parallel, and
  > setting it to `true` will deadlock any handler that calls `script/3`.
  """
  @spec set_config(Config.t() | non_neg_integer(), boolean()) :: :ok
  def set_config(option, status), do: Native.set_config(Config.to_int(option), status)

  @doc "Seconds to wait for a window to connect. `0` waits forever. Affects `show/2` and `wait/0`."
  @spec set_timeout(non_neg_integer()) :: :ok
  def set_timeout(seconds), do: Native.set_timeout(seconds)

  @doc "Process one event at a time for this window only. See `set_config/2` for the global flag."
  @spec set_event_blocking(window(), boolean()) :: :ok
  def set_event_blocking(window, status), do: Native.set_event_blocking(window, status)

  # -- Processes ---------------------------------------------------------

  @doc "OS process ID of the backend, i.e. this application."
  @spec get_parent_process_id(window()) :: non_neg_integer()
  def get_parent_process_id(window), do: Native.get_parent_process_id(window)

  @doc "OS process ID of the browser window."
  @spec get_child_process_id(window()) :: non_neg_integer()
  def get_child_process_id(window), do: Native.get_child_process_id(window)

  # -- Utilities ---------------------------------------------------------

  @doc "Base64-encode a string."
  @spec encode(binary()) :: binary()
  def encode(str), do: Native.encode(str)

  @doc "Base64-decode a string."
  @spec decode(binary()) :: binary()
  def decode(str), do: Native.decode(str)

  @doc "The last WebUI error, as `{number, message}`."
  @spec last_error() :: {non_neg_integer(), binary()}
  def last_error, do: {Native.get_last_error_number(), Native.get_last_error_message()}

  @doc "The version of the WebUI C library this binding was built against."
  @spec version() :: binary()
  def version, do: Native.version()
end

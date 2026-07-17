# Builds the WebUI NIF on Linux and macOS. Windows uses Makefile.win (nmake).
#
# WebUI is linked statically, so priv/webui_nif.so is self-contained -- there is
# no webui-2 shared library to find at runtime.
#
# Driven by `mix compile` via elixir_make. To build against a local WebUI
# checkout rather than the bootstrapped one:
#
#   WEBUI_DIR=/path/to/webui/dist WEBUI_INCLUDE=/path/to/webui/include mix compile

MIX_APP_PATH ?= .
PRIV_DIR = $(MIX_APP_PATH)/priv
NIF = $(PRIV_DIR)/webui_nif.so

# Normally supplied by mix.exs; the fallback keeps a bare `make` working.
ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~ts/erts-~ts/include", [code:root_dir(), erlang:system_info(version)]), halt().')

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_M),x86_64)
	ARCH = x64
else ifeq ($(UNAME_M),amd64)
	ARCH = x64
else ifeq ($(UNAME_M),aarch64)
	ARCH = arm64
else ifeq ($(UNAME_M),arm64)
	ARCH = arm64
else ifneq (,$(findstring arm,$(UNAME_M)))
	ARCH = arm
else
	ARCH = $(UNAME_M)
endif

ifeq ($(UNAME_S),Darwin)
	PLATFORM_DIR = webui-macos-clang-$(ARCH)
	# WebUI's WKWebView backend pulls in Cocoa and WebKit.
	PLATFORM_LDFLAGS = -framework Cocoa -framework WebKit -framework CoreGraphics
	# NIFs resolve enif_* against the running VM, hence dynamic_lookup.
	SHARED_FLAGS = -dynamiclib -undefined dynamic_lookup
else
	PLATFORM_DIR = webui-linux-gcc-$(ARCH)
	PLATFORM_LDFLAGS = -lpthread -lm
	SHARED_FLAGS = -shared
endif

# WEBUI_DIR overrides where the static library is found; WEBUI_INCLUDE does the
# same for webui.h and defaults to sitting beside the library.
ifeq ($(strip $(WEBUI_DIR)),)
	WEBUI_LIB_DIR = $(PLATFORM_DIR)
else
	WEBUI_LIB_DIR = $(WEBUI_DIR)
endif

ifeq ($(strip $(WEBUI_INCLUDE)),)
	WEBUI_INCLUDE_DIR = $(WEBUI_LIB_DIR)
else
	WEBUI_INCLUDE_DIR = $(WEBUI_INCLUDE)
endif

WEBUI_STATIC = $(WEBUI_LIB_DIR)/libwebui-2-static.a

CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wno-unused-parameter -fPIC
CFLAGS += -I"$(ERTS_INCLUDE_DIR)" -I"$(WEBUI_INCLUDE_DIR)"

SOURCES = c_src/webui_nif.c

all: $(NIF)

$(NIF): $(SOURCES) $(WEBUI_STATIC)
	@mkdir -p $(PRIV_DIR)
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -o $@ $(SOURCES) $(WEBUI_STATIC) $(PLATFORM_LDFLAGS) $(LDFLAGS)

$(WEBUI_STATIC):
	@echo "WebUI static library not found at $(WEBUI_STATIC)"
	@echo ""
	@echo "Fetch it with:"
	@echo "    bash bootstrap.sh"
	@echo ""
	@echo "Or point the build at a local WebUI checkout:"
	@echo "    WEBUI_DIR=/path/to/webui/dist WEBUI_INCLUDE=/path/to/webui/include mix compile"
	@false

clean:
	rm -f $(NIF)

.PHONY: all clean

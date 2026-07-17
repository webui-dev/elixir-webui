defmodule WebUI.Browser do
  @moduledoc """
  Web browser identifiers, mirroring `enum webui_browser`.

  Used with `WebUI.show_browser/3` and `WebUI.browser_exist/1`.
  """

  @browsers %{
    no_browser: 0,
    any: 1,
    chrome: 2,
    firefox: 3,
    edge: 4,
    safari: 5,
    chromium: 6,
    opera: 7,
    brave: 8,
    vivaldi: 9,
    epic: 10,
    yandex: 11,
    chromium_based: 12,
    webview: 13
  }

  @type t ::
          :no_browser
          | :any
          | :chrome
          | :firefox
          | :edge
          | :safari
          | :chromium
          | :opera
          | :brave
          | :vivaldi
          | :epic
          | :yandex
          | :chromium_based
          | :webview

  @by_value Map.new(@browsers, fn {k, v} -> {v, k} end)

  @doc "All known browser atoms."
  @spec list() :: [t()]
  def list, do: Map.keys(@browsers)

  @doc "Convert a browser atom to its C enum value. Integers pass through."
  @spec to_int(t() | non_neg_integer()) :: non_neg_integer()
  def to_int(browser) when is_integer(browser), do: browser

  for {name, value} <- @browsers do
    def to_int(unquote(name)), do: unquote(value)
  end

  @doc "Convert a C enum value back to a browser atom, or `nil` if unknown."
  @spec from_int(non_neg_integer()) :: t() | nil
  def from_int(value), do: Map.get(@by_value, value)
end

defmodule WebUI.Runtime do
  @moduledoc """
  JavaScript/TypeScript runtimes for served `.js`/`.ts` files,
  mirroring `enum webui_runtime`. Used with `WebUI.set_runtime/2`.
  """

  @runtimes %{none: 0, deno: 1, nodejs: 2, bun: 3}
  @type t :: :none | :deno | :nodejs | :bun

  @doc "Convert a runtime atom to its C enum value. Integers pass through."
  @spec to_int(t() | non_neg_integer()) :: non_neg_integer()
  def to_int(runtime) when is_integer(runtime), do: runtime

  for {name, value} <- @runtimes do
    def to_int(unquote(name)), do: unquote(value)
  end
end

defmodule WebUI.EventType do
  @moduledoc """
  Event types, mirroring `enum webui_event`. Carried in `WebUI.Event`'s
  `:type` field.
  """

  @types %{
    0 => :disconnected,
    1 => :connected,
    2 => :mouse_click,
    3 => :navigation,
    4 => :callback
  }

  @type t :: :disconnected | :connected | :mouse_click | :navigation | :callback

  @doc "Convert a C enum value to an event type atom. Unknown values pass through."
  @spec from_int(non_neg_integer()) :: t() | non_neg_integer()
  def from_int(value), do: Map.get(@types, value, value)
end

defmodule WebUI.Config do
  @moduledoc """
  Global behaviour flags, mirroring `webui_config`. Used with
  `WebUI.set_config/2`.

  > #### Two of these need care {: .warning}
  >
  > `:asynchronous_response` is set to `true` when the NIF loads and this
  > binding depends on it. Handlers run in Elixir processes rather than on
  > WebUI's callback thread, so WebUI must wait for an explicit response
  > instead of taking the C callback's return value. Setting it to `false`
  > breaks every bound function.
  >
  > `:ui_event_blocking` is left `false` on purpose, so handlers run in
  > parallel. Setting it to `true` serializes them and will deadlock any
  > handler that calls `WebUI.script/3`.
  """

  @options %{
    show_wait_connection: 0,
    ui_event_blocking: 1,
    folder_monitor: 2,
    multi_client: 3,
    use_cookies: 4,
    asynchronous_response: 5
  }

  @type t ::
          :show_wait_connection
          | :ui_event_blocking
          | :folder_monitor
          | :multi_client
          | :use_cookies
          | :asynchronous_response

  @doc "Convert a config atom to its C enum value. Integers pass through."
  @spec to_int(t() | non_neg_integer()) :: non_neg_integer()
  def to_int(option) when is_integer(option), do: option

  for {name, value} <- @options do
    def to_int(unquote(name)), do: unquote(value)
  end
end

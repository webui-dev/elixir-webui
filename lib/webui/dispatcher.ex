defmodule WebUI.Dispatcher do
  @moduledoc """
  Owns the element-to-function table and turns WebUI callbacks into Elixir calls.

  You should not need to touch this directly -- `WebUI.bind/3` goes through it.

  ## How an event travels

  WebUI runs bound-element callbacks on its own threads, which cannot run
  Elixir. The NIF's C callback therefore does nothing but `enif_send` a
  `{:webui_event, ...}` message here and return. Because the NIF sets
  `asynchronous_response`, WebUI does not treat that return as the answer --
  it blocks the calling thread until someone calls
  `WebUI.Native.set_response/3`, which is the last thing this module does for
  every event it accepts.

  That blocking is the reason this module is written the way it is: **every
  event must be answered exactly once, or the window wedges.** Unhandled
  elements are answered with `""` rather than ignored, and handler crashes are
  caught so the response still goes out.

  Handlers run in supervised tasks rather than in this GenServer, so a handler
  is free to block -- `WebUI.script/3` waits on the browser, for instance --
  without stalling other events, and a crashing handler cannot take the
  dispatcher down with it.

  Events may therefore be in flight concurrently, which is deliberate: WebUI is
  left with `ui_event_blocking` false so it gives each event its own thread,
  and handlers spread across schedulers instead of queueing behind each other.
  Nothing depends on ordering -- `set_response` addresses an event by its
  `event_number`, so answers may come back in any order.
  """

  use GenServer
  require Logger

  alias WebUI.{Event, EventType, Native}

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @doc """
  Bind `fun` to `element` on `window` and return WebUI's bind ID.

  An empty `element` binds every event on the window.
  """
  @spec bind(non_neg_integer(), binary(), (Event.t() -> term())) :: non_neg_integer()
  def bind(window, element, fun) when is_function(fun, 1) do
    GenServer.call(__MODULE__, {:bind, window, element, fun})
  end

  @doc "Drop every handler registered for `window`."
  @spec forget(non_neg_integer()) :: :ok
  def forget(window), do: GenServer.call(__MODULE__, {:forget, window})

  @impl true
  def init(:ok) do
    :ok = Native.set_dispatcher(self())
    {:ok, %{handlers: %{}}}
  end

  @impl true
  def handle_call({:bind, window, element, fun}, _from, state) do
    bind_id = Native.bind(window, element)
    {:reply, bind_id, put_in(state.handlers[{window, element}], fun)}
  end

  def handle_call({:forget, window}, _from, state) do
    handlers = Map.reject(state.handlers, fn {{w, _element}, _fun} -> w == window end)
    {:reply, :ok, %{state | handlers: handlers}}
  end

  @impl true
  def handle_info({:webui_event, window, type, element, event_number, bind_id}, state) do
    case find_handler(state.handlers, window, element) do
      nil ->
        Native.set_response(window, event_number, "")

      fun ->
        event = %Event{
          window: window,
          type: EventType.from_int(type),
          element: element,
          number: event_number,
          bind_id: bind_id
        }

        Task.Supervisor.start_child(WebUI.TaskSupervisor, fn -> run(fun, event) end)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # A handler bound to "" catches every event on the window, so it stands in
  # whenever the specific element has none of its own.
  defp find_handler(handlers, window, element) do
    Map.get(handlers, {window, element}) || Map.get(handlers, {window, ""})
  end

  defp run(fun, %Event{} = event) do
    response =
      try do
        encode(fun.(event))
      catch
        kind, reason ->
          Logger.error("""
          WebUI handler for #{inspect(event.element)} raised (#{kind}): #{inspect(reason)}
          #{Exception.format_stacktrace(__STACKTRACE__)}
          """)

          ""
      end

    Native.set_response(event.window, event.number, response)
  end

  # Handler return values become the JS Promise's resolved value. WebUI's
  # response channel is a string, so everything is flattened to one. Returning
  # structured data is the caller's job -- encode it to JSON and return that.
  defp encode(nil), do: ""
  defp encode(:ok), do: ""
  defp encode(value) when is_binary(value), do: value
  defp encode(true), do: "true"
  defp encode(false), do: "false"
  defp encode(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp encode(value) when is_atom(value), do: Atom.to_string(value)

  defp encode(value) do
    to_string(value)
  rescue
    Protocol.UndefinedError -> inspect(value)
  end
end

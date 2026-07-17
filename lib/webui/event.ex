defmodule WebUI.Event do
  @moduledoc """
  An event delivered to a bound function.

  The fields mirror the parameters WebUI passes to a `webui_interface_bind`
  callback. Arguments sent from JavaScript are not carried in the struct --
  they stay in WebUI and are fetched on demand by `(window, number, index)`,
  which is what the `get_*` functions here do.

      WebUI.bind(win, "my_func", fn e ->
        name = WebUI.Event.get_string(e, 0)
        age = WebUI.Event.get_int(e, 1)
        "Hello \#{name}, age \#{age}"
      end)

  Argument getters are only meaningful while the event is being handled. Once
  the handler returns and the response goes back to WebUI, the event number is
  no longer valid -- do not stash an event and read from it later.
  """

  alias WebUI.Native

  @enforce_keys [:window, :type, :element, :number, :bind_id]
  defstruct [:window, :type, :element, :number, :bind_id]

  @type t :: %__MODULE__{
          window: non_neg_integer(),
          type: WebUI.EventType.t(),
          element: binary(),
          number: non_neg_integer(),
          bind_id: non_neg_integer()
        }

  @doc "Number of bytes in the argument at `index`. Useful for raw payloads."
  @spec get_size(t(), non_neg_integer()) :: non_neg_integer()
  def get_size(%__MODULE__{} = e, index \\ 0), do: Native.get_size_at(e.window, e.number, index)

  @doc "Argument at `index` as a string."
  @spec get_string(t(), non_neg_integer()) :: binary()
  def get_string(%__MODULE__{} = e, index \\ 0), do: Native.get_string_at(e.window, e.number, index)

  @doc "Argument at `index` as an integer."
  @spec get_int(t(), non_neg_integer()) :: integer()
  def get_int(%__MODULE__{} = e, index \\ 0), do: Native.get_int_at(e.window, e.number, index)

  @doc "Argument at `index` as a float."
  @spec get_float(t(), non_neg_integer()) :: float()
  def get_float(%__MODULE__{} = e, index \\ 0), do: Native.get_float_at(e.window, e.number, index)

  @doc "Argument at `index` as a boolean."
  @spec get_bool(t(), non_neg_integer()) :: boolean()
  def get_bool(%__MODULE__{} = e, index \\ 0), do: Native.get_bool_at(e.window, e.number, index)

  @doc """
  Argument at `index` as raw bytes.

  Unlike `get_string/2` this uses the argument's declared size, so it keeps
  embedded NUL bytes instead of truncating at the first one. Use it for data
  sent from JS as a `Uint8Array`.
  """
  @spec get_raw(t(), non_neg_integer()) :: binary()
  def get_raw(%__MODULE__{} = e, index \\ 0), do: Native.get_raw_at(e.window, e.number, index)

  @doc "Refresh only the client that raised this event."
  @spec show_client(t(), binary()) :: boolean()
  def show_client(%__MODULE__{} = e, content), do: Native.show_client(e.window, e.number, content)

  @doc "Close only the client that raised this event."
  @spec close_client(t()) :: :ok
  def close_client(%__MODULE__{} = e), do: Native.close_client(e.window, e.number)

  @doc "Navigate only the client that raised this event."
  @spec navigate_client(t(), binary()) :: :ok
  def navigate_client(%__MODULE__{} = e, url), do: Native.navigate_client(e.window, e.number, url)

  @doc "Run JavaScript in only the client that raised this event."
  @spec run_client(t(), binary()) :: :ok
  def run_client(%__MODULE__{} = e, script), do: Native.run_client(e.window, e.number, script)

  @doc "Send raw bytes to a JS function, for only the client that raised this event."
  @spec send_raw_client(t(), binary(), binary()) :: :ok
  def send_raw_client(%__MODULE__{} = e, function, raw),
    do: Native.send_raw_client(e.window, e.number, function, raw)
end

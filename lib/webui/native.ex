defmodule WebUI.Native do
  @moduledoc false

  # Thin 1:1 surface over the WebUI C API. Every function here is replaced at
  # load time by the NIF in c_src/webui_nif.c; the bodies exist only so the
  # module compiles and so a missing NIF fails loudly instead of silently.
  #
  # Use WebUI, not this module. Nothing here validates arguments -- a wrong
  # type reaches C as a badarg, and a wrong window number reaches WebUI as an
  # unchecked size_t.

  @on_load :load_nif

  def load_nif do
    :webui
    |> :code.priv_dir()
    |> :filename.join(~c"webui_nif")
    |> :erlang.load_nif(0)
  end

  defp nif_missing, do: :erlang.nif_error(:nif_not_loaded)

  # Dispatcher
  def set_dispatcher(_pid), do: nif_missing()

  # Window creation
  def new_window, do: nif_missing()
  def new_window_id(_n), do: nif_missing()
  def get_new_window_id, do: nif_missing()

  # Bind / response
  def bind(_window, _element), do: nif_missing()
  def set_response(_window, _event_number, _response), do: nif_missing()

  # Event arguments
  def get_string_at(_window, _event_number, _index), do: nif_missing()
  def get_int_at(_window, _event_number, _index), do: nif_missing()
  def get_float_at(_window, _event_number, _index), do: nif_missing()
  def get_bool_at(_window, _event_number, _index), do: nif_missing()
  def get_size_at(_window, _event_number, _index), do: nif_missing()
  def get_raw_at(_window, _event_number, _index), do: nif_missing()

  # Per-client
  def show_client(_window, _event_number, _content), do: nif_missing()
  def close_client(_window, _event_number), do: nif_missing()
  def navigate_client(_window, _event_number, _url), do: nif_missing()
  def run_client(_window, _event_number, _script), do: nif_missing()
  def send_raw_client(_window, _event_number, _function, _raw), do: nif_missing()

  # Show / server
  def show(_window, _content), do: nif_missing()
  def show_browser(_window, _content, _browser), do: nif_missing()
  def show_wv(_window, _content), do: nif_missing()
  def start_server(_window, _content), do: nif_missing()

  # Lifecycle
  def wait, do: nif_missing()
  def is_app_running, do: nif_missing()
  def close(_window), do: nif_missing()
  def destroy(_window), do: nif_missing()
  def exit, do: nif_missing()
  def clean, do: nif_missing()
  def is_shown(_window), do: nif_missing()
  def minimize(_window), do: nif_missing()
  def maximize(_window), do: nif_missing()
  def focus(_window), do: nif_missing()

  # Flags
  def set_kiosk(_window, _status), do: nif_missing()
  def set_resizable(_window, _status), do: nif_missing()
  def set_hide(_window, _status), do: nif_missing()
  def set_public(_window, _status), do: nif_missing()
  def set_frameless(_window, _status), do: nif_missing()
  def set_transparent(_window, _status), do: nif_missing()
  def set_high_contrast(_window, _status), do: nif_missing()
  def set_event_blocking(_window, _status), do: nif_missing()
  def is_high_contrast, do: nif_missing()

  # Browser
  def browser_exist(_browser), do: nif_missing()
  def get_best_browser(_window), do: nif_missing()
  def set_browser_folder(_path), do: nif_missing()

  # Geometry
  def set_size(_window, _width, _height), do: nif_missing()
  def set_minimum_size(_window, _width, _height), do: nif_missing()
  def set_position(_window, _x, _y), do: nif_missing()
  def set_center(_window), do: nif_missing()

  # Settings
  def set_config(_option, _status), do: nif_missing()
  def set_timeout(_seconds), do: nif_missing()
  def set_runtime(_window, _runtime), do: nif_missing()
  def set_icon(_window, _icon, _type), do: nif_missing()
  def set_profile(_window, _name, _path), do: nif_missing()
  def set_proxy(_window, _proxy), do: nif_missing()
  def set_custom_parameters(_window, _params), do: nif_missing()
  def set_root_folder(_window, _path), do: nif_missing()
  def set_default_root_folder(_path), do: nif_missing()
  def delete_profile(_window), do: nif_missing()
  def delete_all_profiles, do: nif_missing()

  # JavaScript
  def run(_window, _script), do: nif_missing()
  def script(_window, _script, _timeout, _buffer_size), do: nif_missing()
  def send_raw(_window, _function, _raw), do: nif_missing()

  # URL / ports / process
  def navigate(_window, _url), do: nif_missing()
  def get_url(_window), do: nif_missing()
  def open_url(_url), do: nif_missing()
  def get_port(_window), do: nif_missing()
  def set_port(_window, _port), do: nif_missing()
  def get_free_port, do: nif_missing()
  def get_parent_process_id(_window), do: nif_missing()
  def get_child_process_id(_window), do: nif_missing()

  # Utilities
  def get_mime_type(_file), do: nif_missing()
  def encode(_str), do: nif_missing()
  def decode(_str), do: nif_missing()
  def get_last_error_number, do: nif_missing()
  def get_last_error_message, do: nif_missing()
  def version, do: nif_missing()
end

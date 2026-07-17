# WebUI Elixir - Serve a Folder
#
#   mix run examples/serve_a_folder/serve_a_folder.exs

alias WebUI.Event

root = Path.dirname(__ENV__.file)

win = WebUI.new_window()
WebUI.set_root_folder(win, root)

# An empty element name catches every event on the window, which is how
# connect/disconnect and navigation are observed.
WebUI.bind(win, "", fn
  %Event{type: :connected} ->
    IO.puts("connected")

  %Event{type: :disconnected} ->
    IO.puts("disconnected")

  %Event{type: :navigation} = e ->
    url = Event.get_string(e, 0)
    IO.puts("navigating to #{url}")
    # WebUI blocks its own navigation when this event is bound, so drive it.
    Event.navigate_client(e, url)

  _ ->
    :ok
end)

WebUI.bind(win, "exit_app", fn _e -> WebUI.exit() end)

WebUI.show(win, "index.html")
WebUI.wait()
WebUI.clean()

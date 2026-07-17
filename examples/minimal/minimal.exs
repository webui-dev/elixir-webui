# WebUI Elixir - Minimal Example
#
#   mix run examples/minimal/minimal.exs

win = WebUI.new_window()
WebUI.show(win, ~S(<html><script src="webui.js"></script> Hello World from Elixir! </html>))
WebUI.wait()
WebUI.clean()

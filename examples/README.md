# Examples

Run any of these from the repository root, after building once with `mix setup`
(on Windows, from a Developer Command Prompt):

```sh
mix run examples/minimal/minimal.exs
mix run examples/call_elixir_from_js/call_elixir_from_js.exs
mix run examples/call_js_from_elixir/call_js_from_elixir.exs
mix run examples/serve_a_folder/serve_a_folder.exs
mix run examples/frameless/frameless.exs
```

| Example | Shows |
|---|---|
| [minimal](minimal/minimal.exs) | The smallest window that works |
| [call_elixir_from_js](call_elixir_from_js/call_elixir_from_js.exs) | `WebUI.bind/3`, reading arguments, returning a value to a JS Promise |
| [call_js_from_elixir](call_js_from_elixir/call_js_from_elixir.exs) | `WebUI.run/2` fire-and-forget vs. `WebUI.script/3` with a result |
| [serve_a_folder](serve_a_folder/serve_a_folder.exs) | Serving files from disk, and catching all window events with `bind(win, "", …)` |
| [frameless](frameless/frameless.exs) | A frameless, transparent WebView window with a custom HTML title bar (`show_wv/2`, `set_frameless/2`, `set_transparent/2`) |

Every page must load the bridge with `<script src="webui.js"></script>`. WebUI
generates that file in memory at runtime — it is not a file you provide, and it
will not be found on disk.

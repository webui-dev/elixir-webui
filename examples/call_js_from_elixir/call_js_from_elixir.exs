# WebUI Elixir - Call JavaScript from Elixir
#
#   mix run examples/call_js_from_elixir/call_js_from_elixir.exs

html = ~S"""
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <script src="webui.js"></script>
    <title>Call JavaScript from Elixir</title>
    <style>
      body {
        font-family: 'Arial', sans-serif;
        color: white;
        background: linear-gradient(to right, #507d91, #1c596f, #022737);
        text-align: center;
        font-size: 18px;
      }
      button {
        padding: 10px;
        margin: 10px;
        border-radius: 3px;
        border: 1px solid #ccc;
        background: #3498db;
        color: #fff;
        cursor: pointer;
        font-size: 16px;
      }
      button:hover { background: #c9913d; }
      h1 { text-shadow: -7px 10px 7px rgb(67 57 57 / 76%); }
      #count { font-size: 32px; margin: 20px; }
    </style>
  </head>
  <body>
    <h1>WebUI - Call JavaScript from Elixir</h1>
    <div id="count">0</div>
    <button onclick="increment()">Increment from Elixir</button>
    <button onclick="read_title()">Read title from Elixir</button>

    <script>
      let count = 0;
      function setCount(n) {
        count = n;
        document.getElementById('count').innerText = n;
      }
      function getCount() { return count; }
    </script>
  </body>
</html>
"""

win = WebUI.new_window()

# run/2 fires and forgets -- no result comes back.
WebUI.bind(win, "increment", fn e ->
  # script/3 waits for the browser's answer. `return` is required to get one.
  case WebUI.script(e.window, "return getCount();") do
    {:ok, current} ->
      next = String.to_integer(current) + 1
      WebUI.run(e.window, "setCount(#{next});")
      IO.puts("count is now #{next}")

    {:error, reason} ->
      IO.puts("script failed: #{reason}")
  end
end)

WebUI.bind(win, "read_title", fn e ->
  case WebUI.script(e.window, "return document.title;", timeout: 5) do
    {:ok, title} -> IO.puts("title: #{title}")
    {:error, reason} -> IO.puts("script failed: #{reason}")
  end
end)

WebUI.show(win, html)
WebUI.wait()
WebUI.clean()

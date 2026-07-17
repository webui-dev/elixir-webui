# WebUI Elixir - Call Elixir from JavaScript
#
#   mix run examples/call_elixir_from_js/call_elixir_from_js.exs

alias WebUI.Event

html = ~S"""
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <script src="webui.js"></script>
    <title>Call Elixir from JavaScript</title>
    <style>
      body {
        font-family: 'Arial', sans-serif;
        color: white;
        background: linear-gradient(to right, #507d91, #1c596f, #022737);
        text-align: center;
        font-size: 18px;
      }
      button, input {
        padding: 10px;
        margin: 10px;
        border-radius: 3px;
        border: 1px solid #ccc;
        box-shadow: 0 3px 5px rgba(0,0,0,0.1);
        transition: 0.2s;
      }
      button {
        background: #3498db;
        color: #fff;
        cursor: pointer;
        font-size: 16px;
      }
      h1 { text-shadow: -7px 10px 7px rgb(67 57 57 / 76%); }
      button:hover { background: #c9913d; }
      input:focus { outline: none; border-color: #3498db; }
    </style>
  </head>
  <body>
    <h1>WebUI - Call Elixir from JavaScript</h1>
    <p>Call Elixir functions with arguments (<em>See the logs in your terminal</em>)</p>

    <button onclick="my_function_string('Hello', 'World');">
      Call my_function_string()
    </button>
    <br>
    <button onclick="my_function_integer(123, 456, 789, 12345.6789);">
      Call my_function_integer()
    </button>
    <br>
    <button onclick="my_function_boolean(true, false);">
      Call my_function_boolean()
    </button>
    <br>
    <p>Call an Elixir function that returns a response</p>
    <button onclick="MyJS();">Call my_function_with_response()</button>
    <div>Double: <input type="number" id="MyInputID" value="2"></div>

    <script>
      function MyJS() {
        const input = document.getElementById('MyInputID');
        my_function_with_response(input.value, 2).then((response) => {
          input.value = response;
        });
      }
    </script>
  </body>
</html>
"""

win = WebUI.new_window()

# JavaScript: my_function_string('Hello', 'World')
WebUI.bind(win, "my_function_string", fn e ->
  IO.puts("my_function_string 1: #{Event.get_string(e, 0)}")
  IO.puts("my_function_string 2: #{Event.get_string(e, 1)}")
end)

# JavaScript: my_function_integer(123, 456, 789, 12345.6789)
WebUI.bind(win, "my_function_integer", fn e ->
  IO.puts("my_function_integer 1: #{Event.get_int(e, 0)}")
  IO.puts("my_function_integer 2: #{Event.get_int(e, 1)}")
  IO.puts("my_function_integer 3: #{Event.get_int(e, 2)}")
  IO.puts("my_function_integer 4: #{Event.get_float(e, 3)}")
end)

# JavaScript: my_function_boolean(true, false)
WebUI.bind(win, "my_function_boolean", fn e ->
  IO.puts("my_function_boolean 1: #{Event.get_bool(e, 0)}")
  IO.puts("my_function_boolean 2: #{Event.get_bool(e, 1)}")
end)

# The return value resolves the JS Promise.
WebUI.bind(win, "my_function_with_response", fn e ->
  number = Event.get_int(e, 0)
  times = Event.get_int(e, 1)
  result = number * times
  IO.puts("my_function_with_response: #{number} * #{times} = #{result}")
  result
end)

WebUI.show(win, html)
WebUI.wait()
WebUI.clean()

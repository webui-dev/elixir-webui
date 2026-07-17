# WebUI Elixir - Frameless Example
#
# A frameless, transparent WebView window with a custom HTML title bar. The
# drag region and window controls are driven from the page: CSS marks the bar
# draggable, and the buttons call bound Elixir functions.
#
#   mix run examples/frameless/frameless.exs

html = ~S"""
<html>
  <head>
    <meta charset='UTF-8'>
    <script src="webui.js"></script>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { height: 100%; width: 100%; overflow: hidden; background: transparent; }
      #ui-container {
        height: 100%;
        width: 100%;
        background: rgba(30, 30, 30, 0.95);
        color: #f5f5f5;
        font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
        display: flex;
        flex-direction: column;
        border-radius: 10px;
        backdrop-filter: blur(24px);
        -webkit-backdrop-filter: blur(24px);
        border: 1px solid rgba(255, 255, 255, 0.12);
        overflow: hidden;
      }
      #titlebar {
        height: 48px;
        background: rgba(0, 0, 0, 0.25);
        -webkit-app-region: drag; /* Win32/macOS (Native) */
        --webui-app-region: drag; /* Linux (Custom) */
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 18px;
        flex-shrink: 0;
      }
      #title { font-size: 15px; font-weight: 500; }
      #buttons {
        -webkit-app-region: no-drag;
        display: flex;
        gap: 12px;
      }
      #buttons span {
        width: 14px;
        height: 14px;
        border-radius: 50%;
        cursor: pointer;
        transition: all 0.15s ease-out;
      }
      #buttons span:hover { transform: scale(1.1); filter: brightness(1.15); }
      .buttons span:active { transform: scale(0.9); filter: brightness(0.9); }
      .close { background: #ff5f57; }
      .minimize { background: #ffbd2e; }
      /* .maximize { background: #28c940; } REMOVED */
      #content {
        flex-grow: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        padding: 20px;
        text-align: center;
        overflow: auto;
      }
      #message {
        font-size: 38px;
        font-weight: 200;
        letter-spacing: 0.5px;
        text-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
      }
      #sub-message {
        font-size: 16px;
        font-weight: 300;
        color: rgba(240, 240, 240, 0.7);
        margin-top: 12px;
      }
      #exit-btn {
        margin-top: 28px;
        padding: 10px 28px;
        font-size: 15px;
        font-family: inherit;
        color: #f5f5f5;
        background: rgba(255, 95, 87, 0.15);
        border: 1px solid rgba(255, 95, 87, 0.5);
        border-radius: 8px;
        cursor: pointer;
        transition: all 0.15s ease-out;
      }
      #exit-btn:hover { background: rgba(255, 95, 87, 0.3); border-color: #ff5f57; }
      #exit-btn:active { transform: scale(0.97); }
    </style>
  </head>
  <body>
    <div id='ui-container'>
      <div id='titlebar'>
        <span id='title'>WebUI Frameless WebView Window</span>
        <div id='buttons'>
          <span class='button minimize' onclick='minimize()'></span>
          <span class='button close' onclick='close_win()'></span>
        </div>
      </div>
      <div id='content'>
        <span id='message'>Welcome to Your Elixir WebUI App</span>
        <span id='sub-message'>This is a stylish, frameless Elixir WebUI WebView window.</span>
        <button id='exit-btn' onclick='exit_app()'>Exit</button>
      </div>
    </div>
  </body>
</html>
"""

win = WebUI.new_window()

WebUI.bind(win, "minimize", fn e -> WebUI.minimize(e.window) end)
WebUI.bind(win, "maximize", fn e -> WebUI.maximize(e.window) end)
WebUI.bind(win, "close_win", fn e -> WebUI.close(e.window) end)
WebUI.bind(win, "exit_app", fn _e -> WebUI.exit() end)

WebUI.set_size(win, 800, 600)
WebUI.set_frameless(win, true)
WebUI.set_transparent(win, true)
WebUI.set_resizable(win, false)
WebUI.set_center(win)

# Frameless + transparent are WebView-only features
WebUI.show_wv(win, html)
WebUI.wait()
WebUI.clean()

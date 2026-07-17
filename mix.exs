defmodule WebUI.MixProject do
  use Mix.Project

  @version "2.5.1"
  @source_url "https://github.com/webui-dev/elixir-webui"

  def project do
    [
      app: :webui,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      make_env: &make_env/0,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "WebUI",
      source_url: @source_url
    ] ++ windows_make_opts()
  end

  # One-command setup: fetch Elixir deps, download the WebUI static library for
  # this platform, then build the NIF. Running the download between deps.get and
  # compile is deliberate -- elixir_make must be fetched before compile, and the
  # static library must be present before compile links against it.
  defp aliases do
    [setup: ["deps.get", &run_bootstrap/1, "compile"]]
  end

  # Power users pointing at a local WebUI checkout (WEBUI_DIR) do not need the
  # download and can run `mix deps.get && mix compile` directly instead.
  defp run_bootstrap(_args) do
    command =
      case :os.type() do
        {:win32, _} -> "bootstrap.bat"
        _ -> "bash bootstrap.sh"
      end

    case Mix.shell().cmd(command) do
      0 -> :ok
      status -> Mix.raise("bootstrap failed (exit status #{status})")
    end
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {WebUI.Application, []}
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      # Scoped to a `docs` env so a plain `mix run` / `mix compile` in dev does
      # not drag in ex_doc and its makeup/earmark toolchain. Build docs with:
      #   MIX_ENV=docs mix docs
      {:ex_doc, "~> 0.34", only: :docs, runtime: false}
    ]
  end

  # On Windows the NIF is built with `nmake` against Makefile.win, matching the
  # MSVC-built webui-2-static.lib shipped in the webui-windows-msvc-x64 release.
  defp windows_make_opts do
    case :os.type() do
      {:win32, _} -> [make_executable: "nmake", make_makefile: "Makefile.win"]
      _ -> []
    end
  end

  # WEBUI_DIR / WEBUI_INCLUDE let you build against an existing WebUI checkout
  # instead of what bootstrap fetches:
  #
  #     WEBUI_DIR=/path/to/webui/dist WEBUI_INCLUDE=/path/to/webui/include mix compile
  #
  # Left unset, the Makefiles look in the bootstrapped platform folder.
  defp make_env do
    %{
      "MIX_APP_PATH" => Mix.Project.app_path(),
      "ERTS_INCLUDE_DIR" => erts_include_dir(),
      "WEBUI_DIR" => System.get_env("WEBUI_DIR", ""),
      "WEBUI_INCLUDE" => System.get_env("WEBUI_INCLUDE", "")
    }
  end

  defp erts_include_dir do
    Path.join([
      to_string(:code.root_dir()),
      "erts-#{:erlang.system_info(:version)}",
      "include"
    ])
  end

  defp description do
    "Use any web browser or WebView as GUI, with Elixir in the backend and " <>
      "modern web technologies in the frontend."
  end

  defp package do
    [
      name: "webui",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "WebUI" => "https://webui.me"},
      files: ~w(lib c_src Makefile Makefile.win bootstrap.sh bootstrap.bat
                mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end

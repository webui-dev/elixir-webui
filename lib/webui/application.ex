defmodule WebUI.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The task supervisor must be up before the dispatcher, which hands every
    # incoming event to it.
    children = [
      {Task.Supervisor, name: WebUI.TaskSupervisor},
      WebUI.Dispatcher
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: WebUI.Supervisor)
  end
end

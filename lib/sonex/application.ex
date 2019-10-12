defmodule Sonex.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec, warn: false

  def start(_type, _args) do
    children = [
      # Define workers and child supervisors to be supervised
      worker(Sonex.Discovery, []),
      worker(Sonex.SubMngr, []),
      worker(Sonex.EventMngr, []),
      supervisor(Sonex.Player.Supervisor, [])
    ]

    opts = [strategy: :one_for_one, name: LibAstroEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule RulesEngine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc "Application supervision tree for RulesEngine library."

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Registry for tenant engines
      RulesEngine.Registry
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RulesEngine.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

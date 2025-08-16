defmodule RulesEngine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc "Application supervision tree for RulesEngine library."

  use Application

  @impl true
  def start(_type, _args) do
    # Get cache configuration from application environment
    cache_opts = Application.get_env(:rules_engine, :cache, [])

    children = [
      # Start the Registry for tenant engines
      RulesEngine.Registry,
      # Start the Telemetry backend registry for pluggable monitoring
      RulesEngine.Telemetry.BackendRegistry,
      # Start the Telemetry handler for performance monitoring
      RulesEngine.Telemetry,
      # Start the Compilation cache for performance optimization
      {RulesEngine.CompilationCache, cache_opts},
      # Start the Predicate registry for pluggable predicates
      RulesEngine.Engine.PredicateRegistry,
      # Start the Calculator registry for pluggable calculators
      RulesEngine.Engine.CalculatorRegistry,
      # Start the DSL Plugin registry for custom syntax extensions
      RulesEngine.DSL.PluginRegistry
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RulesEngine.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Attach telemetry handlers after successful start
        RulesEngine.Telemetry.attach_handlers()

        # Register configured calculator providers
        register_calculator_providers()

        {:ok, pid}

      error ->
        error
    end
  end

  defp register_calculator_providers do
    providers = Application.get_env(:rules_engine, :calculator_providers, [])

    Enum.each(providers, fn provider ->
      case RulesEngine.Engine.CalculatorRegistry.register_provider(provider) do
        :ok ->
          :ok

        {:error, reason} ->
          require Logger
          Logger.warning("Failed to register calculator provider #{provider}: #{inspect(reason)}")
      end
    end)
  end
end

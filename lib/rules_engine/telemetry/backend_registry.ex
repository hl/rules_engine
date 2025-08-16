defmodule RulesEngine.Telemetry.BackendRegistry do
  @moduledoc """
  Registry for telemetry backends that process RulesEngine events.

  Manages configuration and dispatch of telemetry events to multiple backends
  simultaneously, allowing host applications to integrate with different
  monitoring systems.

  ## Configuration

  Backends can be configured in application environment:

      config :rules_engine, :telemetry_backends, [
        MyApp.StatsDBackend,
        MyApp.PrometheusBackend,
        RulesEngine.Telemetry.ConsoleBackend
      ]

  Or configured at runtime:

      RulesEngine.Telemetry.BackendRegistry.register_backend(MyApp.CustomBackend)

  ## Backend Execution

  - Backends are called synchronously in registration order
  - Errors in individual backends don't affect other backends
  - Failed backends are logged and continue processing
  - No timeout or circuit breaking (backends should be fast)

  """

  use GenServer
  require Logger

  defstruct [
    # List of backend modules implementing Backend behaviour
    :backends,
    # Metrics for backend performance
    :backend_stats
  ]

  # Client API

  @doc """
  Start the backend registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a backend module.

  The module must implement the RulesEngine.Telemetry.Backend behaviour.
  """
  @spec register_backend(module()) :: :ok | {:error, term()}
  def register_backend(backend_module) do
    GenServer.call(__MODULE__, {:register_backend, backend_module})
  end

  @doc """
  Unregister a backend module.
  """
  @spec unregister_backend(module()) :: :ok
  def unregister_backend(backend_module) do
    GenServer.call(__MODULE__, {:unregister_backend, backend_module})
  end

  @doc """
  List all registered backends.
  """
  @spec list_backends() :: [module()]
  def list_backends do
    GenServer.call(__MODULE__, :list_backends)
  end

  @doc """
  Get backend execution statistics.
  """
  @spec get_backend_stats() :: map()
  def get_backend_stats do
    GenServer.call(__MODULE__, :get_backend_stats)
  end

  @doc """
  Reset backend execution statistics.
  """
  @spec reset_backend_stats() :: :ok
  def reset_backend_stats do
    GenServer.call(__MODULE__, :reset_backend_stats)
  end

  @doc """
  Dispatch an event to all registered backends.

  This is called by the telemetry event handlers to fan out events
  to all configured backends.
  """
  @spec dispatch_event([atom()], map(), map()) :: :ok
  def dispatch_event(event, measurements, metadata) do
    GenServer.cast(__MODULE__, {:dispatch_event, event, measurements, metadata})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Load backends from application config
    configured_backends = Application.get_env(:rules_engine, :telemetry_backends, [])

    state = %__MODULE__{
      backends: configured_backends,
      backend_stats: init_backend_stats(configured_backends)
    }

    Logger.info(
      "BackendRegistry started with #{length(configured_backends)} backends: #{inspect(configured_backends)}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:register_backend, backend_module}, _from, state) do
    if Code.ensure_loaded?(backend_module) do
      if backend_module in state.backends do
        {:reply, {:error, :already_registered}, state}
      else
        new_backends = state.backends ++ [backend_module]
        new_stats = Map.put(state.backend_stats, backend_module, init_backend_stat())

        new_state = %{
          state
          | backends: new_backends,
            backend_stats: new_stats
        }

        Logger.info("Registered telemetry backend: #{backend_module}")
        {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :module_not_found}, state}
    end
  end

  @impl true
  def handle_call({:unregister_backend, backend_module}, _from, state) do
    new_backends = List.delete(state.backends, backend_module)
    new_stats = Map.delete(state.backend_stats, backend_module)

    new_state = %{
      state
      | backends: new_backends,
        backend_stats: new_stats
    }

    Logger.info("Unregistered telemetry backend: #{backend_module}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_backends, _from, state) do
    {:reply, state.backends, state}
  end

  @impl true
  def handle_call(:get_backend_stats, _from, state) do
    {:reply, state.backend_stats, state}
  end

  @impl true
  def handle_call(:reset_backend_stats, _from, state) do
    new_stats = init_backend_stats(state.backends)
    new_state = %{state | backend_stats: new_stats}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:dispatch_event, event, measurements, metadata}, state) do
    start_time = System.monotonic_time()

    new_stats =
      Enum.reduce(state.backends, state.backend_stats, fn backend, stats ->
        backend_start = System.monotonic_time()

        try do
          case backend.handle_event(event, measurements, metadata) do
            :ok ->
              update_backend_stat(stats, backend, :success, backend_start)

            {:error, reason} ->
              Logger.warning("Telemetry backend #{backend} returned error: #{inspect(reason)}")
              update_backend_stat(stats, backend, :error, backend_start)
          end
        rescue
          error ->
            Logger.error("Telemetry backend #{backend} crashed: #{inspect(error)}")
            update_backend_stat(stats, backend, :crash, backend_start)
        end
      end)

    total_duration = System.monotonic_time() - start_time

    # Log slow dispatches
    if total_duration > 1_000_000 do
      # > 1ms is considered slow for telemetry
      duration_ms = System.convert_time_unit(total_duration, :native, :millisecond)
      Logger.warning("Slow telemetry dispatch: #{duration_ms}ms for #{inspect(event)}")
    end

    new_state = %{state | backend_stats: new_stats}
    {:noreply, new_state}
  end

  # Private helpers

  defp init_backend_stats(backends) do
    Map.new(backends, fn backend ->
      {backend, init_backend_stat()}
    end)
  end

  defp init_backend_stat do
    %{
      success_count: 0,
      error_count: 0,
      crash_count: 0,
      total_duration: 0,
      avg_duration: 0,
      last_called: nil
    }
  end

  defp update_backend_stat(stats, backend, result, start_time) do
    current_stat = Map.get(stats, backend, init_backend_stat())
    duration = System.monotonic_time() - start_time

    updated_stat = %{
      current_stat
      | last_called: DateTime.utc_now(),
        total_duration: current_stat.total_duration + duration
    }

    updated_stat =
      case result do
        :success ->
          new_count = updated_stat.success_count + 1

          %{
            updated_stat
            | success_count: new_count,
              avg_duration: div(updated_stat.total_duration, new_count)
          }

        :error ->
          %{updated_stat | error_count: updated_stat.error_count + 1}

        :crash ->
          %{updated_stat | crash_count: updated_stat.crash_count + 1}
      end

    Map.put(stats, backend, updated_stat)
  end
end

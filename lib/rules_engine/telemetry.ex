defmodule RulesEngine.Telemetry do
  @moduledoc """
  Telemetry event handling and metrics collection for RulesEngine.

  Provides handlers for compilation and runtime performance metrics,
  with support for periodic reporting and alerting on performance regressions.
  """

  use GenServer
  require Logger

  @registry_name :rules_engine_telemetry_registry

  defmodule Metrics do
    @moduledoc false
    defstruct [
      :compilation_count,
      :compilation_total_time,
      :compilation_avg_time,
      :compilation_failures,
      :engine_run_count,
      :engine_total_time,
      :engine_avg_time,
      :engine_total_fires,
      :working_memory_peak,
      :agenda_peak,
      :last_reset
    ]

    def new do
      %__MODULE__{
        compilation_count: 0,
        compilation_total_time: 0,
        compilation_avg_time: 0,
        compilation_failures: 0,
        engine_run_count: 0,
        engine_total_time: 0,
        engine_avg_time: 0,
        engine_total_fires: 0,
        working_memory_peak: 0,
        agenda_peak: 0,
        last_reset: DateTime.utc_now()
      }
    end
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :global_metrics,
      # Map of tenant_id -> Metrics
      :tenant_metrics
    ]

    def new do
      %__MODULE__{
        global_metrics: Metrics.new(),
        tenant_metrics: %{}
      }
    end
  end

  # Public API

  @doc """
  Start the telemetry handler.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attach telemetry handlers.
  """
  def attach_handlers do
    handlers = [
      {[:rules_engine, :compile, :start], &__MODULE__.handle_compile_start/4},
      {[:rules_engine, :compile, :stop], &__MODULE__.handle_compile_stop/4},
      {[:rules_engine, :engine, :run, :start], &__MODULE__.handle_engine_start/4},
      {[:rules_engine, :engine, :run, :stop], &__MODULE__.handle_engine_stop/4}
    ]

    Enum.each(handlers, fn {event, handler} ->
      :telemetry.attach("rules_engine_#{Enum.join(event, "_")}", event, handler, %{})
    end)

    Logger.info("RulesEngine telemetry handlers attached")
  end

  @doc """
  Detach all telemetry handlers.
  """
  def detach_handlers do
    events = [
      [:rules_engine, :compile, :start],
      [:rules_engine, :compile, :stop],
      [:rules_engine, :engine, :run, :start],
      [:rules_engine, :engine, :run, :stop]
    ]

    Enum.each(events, fn event ->
      :telemetry.detach("rules_engine_#{Enum.join(event, "_")}")
    end)

    Logger.info("RulesEngine telemetry handlers detached")
  end

  @doc """
  Get current performance metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Get performance metrics for a specific tenant.
  """
  def get_tenant_metrics(tenant_id) do
    GenServer.call(__MODULE__, {:get_tenant_metrics, tenant_id})
  end

  @doc """
  Get list of all tenant IDs with metrics.
  """
  def list_tenants do
    GenServer.call(__MODULE__, :list_tenants)
  end

  @doc """
  Reset all metrics (global and per-tenant).
  """
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end

  @doc """
  Reset metrics for a specific tenant.
  """
  def reset_tenant_metrics(tenant_id) do
    GenServer.call(__MODULE__, {:reset_tenant_metrics, tenant_id})
  end

  @doc """
  Generate a performance report.
  """
  def performance_report(tenant_id \\ nil) do
    case tenant_id do
      nil -> global_performance_report()
      tenant_id -> tenant_performance_report(tenant_id)
    end
  end

  defp global_performance_report do
    state = GenServer.call(__MODULE__, :get_state)
    metrics = state.global_metrics
    tenant_count = map_size(state.tenant_metrics)

    """
    RulesEngine Global Performance Report
    =====================================

    Overall Statistics:
    - Active tenants: #{tenant_count}

    Global Compilation Metrics:
    - Total compilations: #{metrics.compilation_count}
    - Average compilation time: #{format_duration(metrics.compilation_avg_time)}
    - Total compilation time: #{format_duration(metrics.compilation_total_time)}
    - Compilation failures: #{metrics.compilation_failures}

    Global Engine Runtime Metrics:
    - Total engine runs: #{metrics.engine_run_count}
    - Average run time: #{format_duration(metrics.engine_avg_time)}
    - Total runtime: #{format_duration(metrics.engine_total_time)}
    - Total rule fires: #{metrics.engine_total_fires}
    - Peak working memory size: #{metrics.working_memory_peak}
    - Peak agenda size: #{metrics.agenda_peak}

    Report generated: #{DateTime.utc_now()}
    Metrics since: #{metrics.last_reset}
    """
  end

  defp tenant_performance_report(tenant_id) do
    case get_tenant_metrics(tenant_id) do
      nil ->
        """
        No metrics found for tenant: #{tenant_id}
        """

      metrics ->
        """
        RulesEngine Tenant Performance Report
        =====================================
        Tenant ID: #{tenant_id}

        Compilation Metrics:
        - Total compilations: #{metrics.compilation_count}
        - Average compilation time: #{format_duration(metrics.compilation_avg_time)}
        - Total compilation time: #{format_duration(metrics.compilation_total_time)}
        - Compilation failures: #{metrics.compilation_failures}

        Engine Runtime Metrics:
        - Total engine runs: #{metrics.engine_run_count}
        - Average run time: #{format_duration(metrics.engine_avg_time)}
        - Total runtime: #{format_duration(metrics.engine_total_time)}
        - Total rule fires: #{metrics.engine_total_fires}
        - Peak working memory size: #{metrics.working_memory_peak}
        - Peak agenda size: #{metrics.agenda_peak}

        Report generated: #{DateTime.utc_now()}
        Metrics since: #{metrics.last_reset}
        """
    end
  end

  # Telemetry event handlers

  def handle_compile_start(_event, _measurements, metadata, _config) do
    Logger.debug("Compilation started",
      tenant_id: metadata.tenant_id,
      source_size: metadata.source_size
    )
  end

  def handle_compile_stop(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    GenServer.cast(
      __MODULE__,
      {:compilation_complete,
       %{
         duration: measurements.duration,
         result: metadata.result,
         tenant_id: metadata.tenant_id,
         rules_count: Map.get(metadata, :rules_count, 0)
       }}
    )

    Logger.debug("Compilation completed",
      tenant_id: metadata.tenant_id,
      result: metadata.result,
      duration_ms: duration_ms,
      rules_count: Map.get(metadata, :rules_count, 0)
    )
  end

  def handle_engine_start(_event, _measurements, metadata, _config) do
    Logger.debug("Engine run started",
      tenant_id: metadata.tenant_id,
      agenda_size: metadata.agenda_size,
      working_memory_size: metadata.working_memory_size
    )
  end

  def handle_engine_stop(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    GenServer.cast(
      __MODULE__,
      {:engine_run_complete,
       %{
         duration: measurements.duration,
         fires_executed: metadata.fires_executed,
         tenant_id: metadata.tenant_id,
         agenda_size_after: metadata.agenda_size_after,
         working_memory_size_after: metadata.working_memory_size_after
       }}
    )

    Logger.debug("Engine run completed",
      tenant_id: metadata.tenant_id,
      duration_ms: duration_ms,
      fires_executed: metadata.fires_executed,
      agenda_size_after: metadata.agenda_size_after
    )
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Registry.start_link(keys: :unique, name: @registry_name)
    {:ok, State.new()}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.global_metrics, state}
  end

  @impl true
  def handle_call({:get_tenant_metrics, tenant_id}, _from, state) do
    tenant_metrics = Map.get(state.tenant_metrics, tenant_id)
    {:reply, tenant_metrics, state}
  end

  @impl true
  def handle_call(:list_tenants, _from, state) do
    tenant_ids = Map.keys(state.tenant_metrics)
    {:reply, tenant_ids, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:reset_metrics, _from, _state) do
    new_state = State.new()
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:reset_tenant_metrics, tenant_id}, _from, state) do
    new_tenant_metrics = Map.delete(state.tenant_metrics, tenant_id)
    new_state = %{state | tenant_metrics: new_tenant_metrics}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:compilation_complete, data}, state) do
    tenant_id = data.tenant_id

    # Update global metrics
    new_global_metrics = update_compilation_metrics(state.global_metrics, data)

    # Update tenant-specific metrics
    tenant_metrics = Map.get(state.tenant_metrics, tenant_id, Metrics.new())
    new_tenant_metrics = update_compilation_metrics(tenant_metrics, data)

    new_state = %{
      state
      | global_metrics: new_global_metrics,
        tenant_metrics: Map.put(state.tenant_metrics, tenant_id, new_tenant_metrics)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:engine_run_complete, data}, state) do
    tenant_id = data.tenant_id

    # Update global metrics
    new_global_metrics = update_engine_metrics(state.global_metrics, data)

    # Update tenant-specific metrics
    tenant_metrics = Map.get(state.tenant_metrics, tenant_id, Metrics.new())
    new_tenant_metrics = update_engine_metrics(tenant_metrics, data)

    new_state = %{
      state
      | global_metrics: new_global_metrics,
        tenant_metrics: Map.put(state.tenant_metrics, tenant_id, new_tenant_metrics)
    }

    {:noreply, new_state}
  end

  # Private helpers

  defp update_compilation_metrics(metrics, data) do
    case data.result do
      :success ->
        new_count = metrics.compilation_count + 1
        new_total = metrics.compilation_total_time + data.duration
        new_avg = div(new_total, new_count)

        %{
          metrics
          | compilation_count: new_count,
            compilation_total_time: new_total,
            compilation_avg_time: new_avg
        }

      :error ->
        %{metrics | compilation_failures: metrics.compilation_failures + 1}
    end
  end

  defp update_engine_metrics(metrics, data) do
    new_count = metrics.engine_run_count + 1
    new_total_time = metrics.engine_total_time + data.duration
    new_avg_time = div(new_total_time, new_count)
    new_total_fires = metrics.engine_total_fires + data.fires_executed
    new_wm_peak = max(metrics.working_memory_peak, data.working_memory_size_after)
    new_agenda_peak = max(metrics.agenda_peak, data.agenda_size_after)

    %{
      metrics
      | engine_run_count: new_count,
        engine_total_time: new_total_time,
        engine_avg_time: new_avg_time,
        engine_total_fires: new_total_fires,
        working_memory_peak: new_wm_peak,
        agenda_peak: new_agenda_peak
    }
  end

  defp format_duration(duration_native) when is_integer(duration_native) do
    duration_ms = System.convert_time_unit(duration_native, :native, :millisecond)
    "#{duration_ms}ms"
  end

  defp format_duration(nil), do: "0ms"
end

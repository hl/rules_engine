defmodule RulesEngine.Telemetry.ConsoleBackend do
  @moduledoc """
  Console logging backend for RulesEngine telemetry events.

  Logs telemetry events to the console using the Logger module.
  Useful for development, debugging, and basic monitoring.

  ## Configuration

      config :rules_engine, :telemetry_backends, [
        RulesEngine.Telemetry.ConsoleBackend
      ]

  ## Log Format

  Events are logged at debug level with structured metadata:

      09:30:15.123 [debug] [telemetry] rules_engine.compile.stop duration=45ms result=success tenant=tenant1 rules=5

  """

  @behaviour RulesEngine.Telemetry.Backend

  require Logger

  @impl true
  def handle_event([:rules_engine, :compile, :start], _measurements, metadata) do
    Logger.debug("[telemetry] rules_engine.compile.start",
      tenant: metadata.tenant_id,
      source_size: metadata.source_size
    )

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :compile, :stop], measurements, metadata) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("[telemetry] rules_engine.compile.stop",
      tenant: metadata.tenant_id,
      result: metadata.result,
      duration_ms: duration_ms,
      rules_count: Map.get(metadata, :rules_count, 0)
    )

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :engine, :run, :start], _measurements, metadata) do
    Logger.debug("[telemetry] rules_engine.engine.run.start",
      tenant: metadata.tenant_id,
      agenda_size: metadata.agenda_size,
      working_memory_size: metadata.working_memory_size,
      fire_limit: metadata.fire_limit
    )

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :engine, :run, :stop], measurements, metadata) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("[telemetry] rules_engine.engine.run.stop",
      tenant: metadata.tenant_id,
      duration_ms: duration_ms,
      fires_executed: metadata.fires_executed,
      agenda_size_after: metadata.agenda_size_after,
      working_memory_size_after: metadata.working_memory_size_after
    )

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :memory, :eviction], measurements, metadata) do
    Logger.warning("[telemetry] rules_engine.memory.eviction",
      tenant: metadata.tenant_key,
      evicted_count: measurements.evicted_count,
      requested_count: measurements.requested_count
    )

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :cache, :hit], _measurements, metadata) do
    Logger.debug("[telemetry] rules_engine.cache.hit",
      cache_key: metadata.cache_key
    )

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :cache, :miss], _measurements, metadata) do
    Logger.debug("[telemetry] rules_engine.cache.miss",
      cache_key: metadata.cache_key
    )

    :ok
  end

  @impl true
  def handle_event(event, measurements, metadata) do
    # Log unknown events for debugging
    Logger.debug("[telemetry] #{Enum.join(event, ".")}",
      measurements: measurements,
      metadata: metadata
    )

    :ok
  end
end

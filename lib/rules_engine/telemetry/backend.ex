defmodule RulesEngine.Telemetry.Backend do
  @moduledoc """
  Behaviour for telemetry backends that process RulesEngine events.

  Allows host applications to integrate with different monitoring systems
  like StatsD, Prometheus, DataDog, New Relic, or custom logging.

  ## Example Implementation

      defmodule MyApp.RulesEngineTelemetry do
        @behaviour RulesEngine.Telemetry.Backend

        def handle_event([:rules_engine, :compile, :stop], measurements, metadata) do
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
          
          MyApp.Metrics.timing("rules_engine.compilation.duration", duration_ms,
            tags: ["tenant:" <> to_string(metadata.tenant_id), "result:" <> to_string(metadata.result)])
        end

        def handle_event([:rules_engine, :engine, :run, :stop], measurements, metadata) do
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
          
          MyApp.Metrics.timing("rules_engine.execution.duration", duration_ms,
            tags: ["tenant:" <> to_string(metadata.tenant_id)])
          
          MyApp.Metrics.count("rules_engine.execution.fires", metadata.fires_executed,
            tags: ["tenant:" <> to_string(metadata.tenant_id)])
        end

        # Handle other events...
        def handle_event(_event, _measurements, _metadata), do: :ok
      end

  ## Configuration

      # In application configuration
      config :rules_engine, :telemetry_backends, [
        MyApp.RulesEngineTelemetry,
        RulesEngine.Telemetry.ConsoleBackend
      ]

  """

  @doc """
  Handle a telemetry event with measurements and metadata.

  Called for each telemetry event emitted by RulesEngine components.
  Backend implementations should process the event according to their
  monitoring system requirements.

  ## Parameters

  - `event` - List of atoms representing the event name
  - `measurements` - Map of numeric measurements (duration, counts, etc.)
  - `metadata` - Map of contextual information (tenant_id, result, etc.)

  ## Events

  ### Compilation Events

  - `[:rules_engine, :compile, :start]`
    - measurements: `%{}`
    - metadata: `%{tenant_id: term(), source_size: integer()}`

  - `[:rules_engine, :compile, :stop]`
    - measurements: `%{duration: integer()}`
    - metadata: `%{tenant_id: term(), result: :success | :error, rules_count: integer()}`

  ### Engine Runtime Events

  - `[:rules_engine, :engine, :run, :start]`
    - measurements: `%{}`
    - metadata: `%{tenant_id: term(), agenda_size: integer(), working_memory_size: integer(), fire_limit: integer()}`

  - `[:rules_engine, :engine, :run, :stop]`
    - measurements: `%{duration: integer()}`
    - metadata: `%{tenant_id: term(), fires_executed: integer(), agenda_size_after: integer(), working_memory_size_after: integer()}`

  ### Memory Management Events

  - `[:rules_engine, :memory, :eviction]`
    - measurements: `%{evicted_count: integer(), requested_count: integer()}`
    - metadata: `%{tenant_key: term()}`

  ### Cache Events

  - `[:rules_engine, :cache, :hit]`
    - measurements: `%{}`
    - metadata: `%{cache_key: binary()}`

  - `[:rules_engine, :cache, :miss]`
    - measurements: `%{}`
    - metadata: `%{cache_key: binary()}`

  """
  @callback handle_event(
              event :: [atom()],
              measurements :: map(),
              metadata :: map()
            ) :: :ok | {:error, term()}
end

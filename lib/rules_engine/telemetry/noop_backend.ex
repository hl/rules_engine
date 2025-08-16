defmodule RulesEngine.Telemetry.NoopBackend do
  @moduledoc """
  No-operation backend for RulesEngine telemetry events.

  Discards all telemetry events with minimal overhead.
  Useful for production environments where telemetry collection
  needs to be disabled for performance reasons.

  ## Configuration

      config :rules_engine, :telemetry_backends, [
        RulesEngine.Telemetry.NoopBackend
      ]

  ## Performance

  This backend has virtually zero overhead - it simply returns :ok
  for all events without processing them.

  """

  @behaviour RulesEngine.Telemetry.Backend

  @impl true
  def handle_event(_event, _measurements, _metadata) do
    :ok
  end
end

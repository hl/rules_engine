defmodule RulesEngine.Telemetry.StatsdBackend do
  @moduledoc """
  StatsD backend for RulesEngine telemetry events.

  Sends metrics to StatsD-compatible systems like DataDog, Grafana Cloud,
  InfluxDB, or Prometheus StatsD exporter.

  ## Configuration

      config :rules_engine, :telemetry_backends, [
        RulesEngine.Telemetry.StatsdBackend
      ]

      config :rules_engine, :statsd,
        host: "localhost",
        port: 8125,
        prefix: "rules_engine",
        tags: ["env:production", "service:rules_engine"]

  ## Metrics

  The following metrics are sent to StatsD:

  - `rules_engine.compilation.duration` (timing) - Compilation time in milliseconds
  - `rules_engine.compilation.count` (counter) - Number of compilations
  - `rules_engine.compilation.errors` (counter) - Number of compilation errors
  - `rules_engine.engine.duration` (timing) - Engine run duration in milliseconds
  - `rules_engine.engine.fires` (counter) - Number of rule fires
  - `rules_engine.engine.working_memory_size` (gauge) - Working memory size
  - `rules_engine.engine.agenda_size` (gauge) - Agenda size
  - `rules_engine.memory.evictions` (counter) - Memory eviction events
  - `rules_engine.cache.hits` (counter) - Cache hit events
  - `rules_engine.cache.misses` (counter) - Cache miss events

  All metrics include tenant_id tags when available.

  ## UDP Client

  Uses a simple UDP client for maximum performance and minimal overhead.
  Does not wait for responses or handle connection failures gracefully -
  this is by design for telemetry systems where availability > accuracy.

  """

  @behaviour RulesEngine.Telemetry.Backend

  require Logger

  @impl true
  def handle_event([:rules_engine, :compile, :start], _measurements, metadata) do
    send_counter("compilation.count", 1, tags_for_tenant(metadata.tenant_id))
    :ok
  end

  @impl true
  def handle_event([:rules_engine, :compile, :stop], measurements, metadata) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    base_tags = tags_for_tenant(metadata.tenant_id)

    send_timing("compilation.duration", duration_ms, base_tags)

    case metadata.result do
      :success ->
        send_counter("compilation.success", 1, base_tags)

      :error ->
        send_counter("compilation.errors", 1, base_tags)
    end

    if rules_count = Map.get(metadata, :rules_count) do
      send_gauge("compilation.rules_count", rules_count, base_tags)
    end

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :engine, :run, :start], _measurements, metadata) do
    base_tags = tags_for_tenant(metadata.tenant_id)

    send_gauge("engine.agenda_size", metadata.agenda_size, base_tags)
    send_gauge("engine.working_memory_size", metadata.working_memory_size, base_tags)

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :engine, :run, :stop], measurements, metadata) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    base_tags = tags_for_tenant(metadata.tenant_id)

    send_timing("engine.duration", duration_ms, base_tags)
    send_counter("engine.fires", metadata.fires_executed, base_tags)
    send_gauge("engine.agenda_size_after", metadata.agenda_size_after, base_tags)
    send_gauge("engine.working_memory_size_after", metadata.working_memory_size_after, base_tags)

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :memory, :eviction], measurements, metadata) do
    base_tags = tags_for_tenant(metadata.tenant_key)

    send_counter("memory.evictions", 1, base_tags)
    send_counter("memory.evicted_facts", measurements.evicted_count, base_tags)

    :ok
  end

  @impl true
  def handle_event([:rules_engine, :cache, :hit], _measurements, _metadata) do
    send_counter("cache.hits", 1, [])
    :ok
  end

  @impl true
  def handle_event([:rules_engine, :cache, :miss], _measurements, _metadata) do
    send_counter("cache.misses", 1, [])
    :ok
  end

  @impl true
  def handle_event(_event, _measurements, _metadata) do
    # Ignore unknown events
    :ok
  end

  # Private helpers

  defp tags_for_tenant(tenant_id) do
    ["tenant:#{tenant_id}"]
  end

  defp send_timing(metric, value, tags) do
    send_metric("#{metric}:#{value}|ms#{format_tags(tags)}")
  end

  defp send_counter(metric, value, tags) do
    send_metric("#{metric}:#{value}|c#{format_tags(tags)}")
  end

  defp send_gauge(metric, value, tags) do
    send_metric("#{metric}:#{value}|g#{format_tags(tags)}")
  end

  defp send_metric(message) do
    config = Application.get_env(:rules_engine, :statsd, [])
    host = Keyword.get(config, :host, "localhost")
    port = Keyword.get(config, :port, 8125)
    prefix = Keyword.get(config, :prefix, "rules_engine")

    full_message = "#{prefix}.#{message}"

    case :gen_udp.open(0) do
      {:ok, socket} ->
        :gen_udp.send(socket, String.to_charlist(host), port, full_message)
        :gen_udp.close(socket)

      {:error, reason} ->
        Logger.warning("Failed to send StatsD metric: #{reason}")
    end
  end

  defp format_tags([]), do: ""

  defp format_tags(tags) when is_list(tags) do
    global_tags =
      Application.get_env(:rules_engine, :statsd, [])
      |> Keyword.get(:tags, [])

    all_tags = global_tags ++ tags
    "|##{Enum.join(all_tags, ",")}"
  end
end

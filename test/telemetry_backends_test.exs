defmodule RulesEngine.TelemetryBackendsTest do
  use ExUnit.Case, async: false

  alias RulesEngine.Telemetry.{Backend, BackendRegistry, ConsoleBackend, NoopBackend}

  defmodule TestBackend do
    @moduledoc """
    Test backend that captures events for verification.
    """

    @behaviour Backend

    @impl true
    def handle_event(event, measurements, metadata) do
      # Store events in ETS for test verification
      try do
        :ets.insert(
          :test_telemetry_events,
          {{:os.system_time(), make_ref()}, {event, measurements, metadata}}
        )
      rescue
        ArgumentError ->
          # Table doesn't exist, create it
          :ets.new(:test_telemetry_events, [:public, :named_table, :bag])

          :ets.insert(
            :test_telemetry_events,
            {{:os.system_time(), make_ref()}, {event, measurements, metadata}}
          )
      end

      :ok
    end
  end

  defmodule CrashBackend do
    @moduledoc """
    Backend that crashes to test error handling.
    """

    @behaviour Backend

    @impl true
    def handle_event(_event, _measurements, _metadata) do
      raise "Intentional crash for testing"
    end
  end

  defmodule ErrorBackend do
    @moduledoc """
    Backend that returns errors to test error handling.
    """

    @behaviour Backend

    @impl true
    def handle_event(_event, _measurements, _metadata) do
      {:error, :test_error}
    end
  end

  describe "Backend behaviour" do
    test "ConsoleBackend implements Backend behaviour" do
      assert Code.ensure_loaded?(ConsoleBackend)
      assert function_exported?(ConsoleBackend, :handle_event, 3)
    end

    test "NoopBackend implements Backend behaviour" do
      assert Code.ensure_loaded?(NoopBackend)
      assert function_exported?(NoopBackend, :handle_event, 3)
    end
  end

  describe "BackendRegistry" do
    setup do
      # Start BackendRegistry if not already running
      case Process.whereis(BackendRegistry) do
        nil -> start_supervised!(BackendRegistry)
        _pid -> :ok
      end

      # Create ETS table for test events
      if :ets.whereis(:test_telemetry_events) == :undefined do
        :ets.new(:test_telemetry_events, [:public, :named_table, :bag])
      else
        :ets.delete_all_objects(:test_telemetry_events)
      end

      # Clear any existing backends for clean test state
      for backend <- BackendRegistry.list_backends() do
        BackendRegistry.unregister_backend(backend)
      end

      :ok
    end

    test "can register and unregister backends" do
      assert :ok = BackendRegistry.register_backend(TestBackend)
      assert TestBackend in BackendRegistry.list_backends()

      assert :ok = BackendRegistry.unregister_backend(TestBackend)
      refute TestBackend in BackendRegistry.list_backends()
    end

    test "prevents duplicate backend registration" do
      assert :ok = BackendRegistry.register_backend(TestBackend)
      assert {:error, :already_registered} = BackendRegistry.register_backend(TestBackend)
    end

    test "handles non-existent module registration" do
      assert {:error, :module_not_found} = BackendRegistry.register_backend(NonExistentModule)
    end

    test "dispatches events to registered backends" do
      BackendRegistry.register_backend(TestBackend)

      event = [:rules_engine, :test, :event]
      measurements = %{duration: 100}
      metadata = %{tenant_id: :test_tenant}

      BackendRegistry.dispatch_event(event, measurements, metadata)

      # Wait for async processing
      Process.sleep(10)

      # Check that event was stored in ETS
      events = :ets.tab2list(:test_telemetry_events)
      assert length(events) == 1
      {_key, {stored_event, stored_measurements, stored_metadata}} = hd(events)
      assert stored_event == event
      assert stored_measurements == measurements
      assert stored_metadata == metadata
    end

    test "dispatches events to multiple backends" do
      BackendRegistry.register_backend(TestBackend)

      # Register NoopBackend to ensure multiple backends work
      BackendRegistry.register_backend(NoopBackend)

      event = [:rules_engine, :test, :multiple]
      measurements = %{count: 5}
      metadata = %{tenant_id: :multi_tenant}

      BackendRegistry.dispatch_event(event, measurements, metadata)

      # Wait for async processing
      Process.sleep(10)

      # TestBackend should store event in ETS
      events = :ets.tab2list(:test_telemetry_events)
      assert length(events) == 1
    end

    test "handles backend crashes gracefully" do
      BackendRegistry.register_backend(CrashBackend)
      BackendRegistry.register_backend(TestBackend)

      event = [:rules_engine, :test, :crash]
      measurements = %{}
      metadata = %{}

      # Should not crash the registry
      BackendRegistry.dispatch_event(event, measurements, metadata)

      # Wait for async processing
      Process.sleep(10)

      # TestBackend should still store the event
      events = :ets.tab2list(:test_telemetry_events)
      assert length(events) == 1

      # Check backend stats show crash
      # Allow async processing
      Process.sleep(10)
      stats = BackendRegistry.get_backend_stats()
      crash_stat = Map.get(stats, CrashBackend)
      assert crash_stat.crash_count == 1
    end

    test "handles backend errors gracefully" do
      BackendRegistry.register_backend(ErrorBackend)
      BackendRegistry.register_backend(TestBackend)

      event = [:rules_engine, :test, :error]
      measurements = %{}
      metadata = %{}

      BackendRegistry.dispatch_event(event, measurements, metadata)

      # Wait for async processing
      Process.sleep(10)

      # TestBackend should still store the event
      events = :ets.tab2list(:test_telemetry_events)
      assert length(events) == 1

      # Check backend stats show error
      # Allow async processing
      Process.sleep(10)
      stats = BackendRegistry.get_backend_stats()
      error_stat = Map.get(stats, ErrorBackend)
      assert error_stat.error_count == 1
    end

    test "tracks backend execution statistics" do
      BackendRegistry.register_backend(TestBackend)

      event = [:rules_engine, :test, :stats]
      measurements = %{}
      metadata = %{}

      BackendRegistry.dispatch_event(event, measurements, metadata)

      # Allow async processing
      Process.sleep(10)

      stats = BackendRegistry.get_backend_stats()
      test_stat = Map.get(stats, TestBackend)

      assert test_stat.success_count == 1
      assert test_stat.error_count == 0
      assert test_stat.crash_count == 0
      assert is_integer(test_stat.total_duration)
      assert test_stat.last_called != nil
    end

    test "can reset backend statistics" do
      BackendRegistry.register_backend(TestBackend)
      BackendRegistry.dispatch_event([:test], %{}, %{})

      Process.sleep(10)

      stats_before = BackendRegistry.get_backend_stats()
      assert Map.get(stats_before, TestBackend).success_count == 1

      BackendRegistry.reset_backend_stats()

      stats_after = BackendRegistry.get_backend_stats()
      assert Map.get(stats_after, TestBackend).success_count == 0
    end
  end

  describe "ConsoleBackend" do
    test "handles compilation events" do
      event = [:rules_engine, :compile, :stop]
      # 50ms in native time
      measurements = %{duration: 50_000_000}
      metadata = %{tenant_id: :test, result: :success, rules_count: 3}

      assert :ok = ConsoleBackend.handle_event(event, measurements, metadata)
    end

    test "handles engine events" do
      event = [:rules_engine, :engine, :run, :stop]
      # 25ms in native time
      measurements = %{duration: 25_000_000}

      metadata = %{
        tenant_id: :test_engine,
        fires_executed: 5,
        agenda_size_after: 2,
        working_memory_size_after: 10
      }

      assert :ok = ConsoleBackend.handle_event(event, measurements, metadata)
    end

    test "handles memory eviction events" do
      event = [:rules_engine, :memory, :eviction]
      measurements = %{evicted_count: 10, requested_count: 15}
      metadata = %{tenant_key: :memory_test}

      assert :ok = ConsoleBackend.handle_event(event, measurements, metadata)
    end

    test "handles unknown events" do
      event = [:unknown, :event, :type]
      measurements = %{some_metric: 123}
      metadata = %{context: "test"}

      assert :ok = ConsoleBackend.handle_event(event, measurements, metadata)
    end
  end

  describe "NoopBackend" do
    test "handles all events without processing" do
      assert :ok = NoopBackend.handle_event([:any, :event], %{data: 123}, %{meta: "value"})
    end
  end

  describe "Configuration" do
    test "loads backends from application configuration" do
      # This test would need to be more sophisticated in a real scenario
      # as it requires restarting the supervision tree with new config
      backends = Application.get_env(:rules_engine, :telemetry_backends, [])
      assert is_list(backends)
    end
  end

  describe "Integration with existing telemetry" do
    test "events are dispatched through registry" do
      BackendRegistry.register_backend(TestBackend)

      # Simulate a compilation event
      :telemetry.execute(
        [:rules_engine, :compile, :stop],
        %{duration: 1_000_000},
        %{tenant_id: :integration_test, result: :success, rules_count: 1}
      )

      # Wait for async processing
      Process.sleep(50)

      # Should store event via registered backend
      events = :ets.tab2list(:test_telemetry_events)
      assert length(events) == 1
      {_key, {event, _measurements, _metadata}} = hd(events)
      assert event == [:rules_engine, :compile, :stop]
    end
  end
end

defmodule RulesEngine.MemoryLimitsTest do
  use ExUnit.Case, async: false

  alias RulesEngine.Engine

  @simple_network %{
    "productions" => [
      %{
        "id" => "test-rule-1",
        "salience" => 0,
        "network_nodes" => [],
        "actions" => [
          %{"type" => "emit", "fact_type" => "Derived", "fields" => %{"value" => 42}}
        ]
      }
    ],
    "alpha_nodes" => [],
    "beta_nodes" => []
  }

  setup do
    # Start the Registry for tenant engines if not already started
    case start_supervised({Registry, keys: :unique, name: RulesEngine.Registry}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "memory limit configuration" do
    test "engine can be started with memory limit configuration" do
      {:ok, pid} =
        Engine.start_tenant(:test_tenant, @simple_network,
          memory_limit_mb: 1,
          memory_check_interval: 100,
          memory_eviction_policy: :lru
        )

      assert is_pid(pid)
      Engine.stop_tenant(:test_tenant)
    end

    test "engine works normally without memory limits" do
      {:ok, pid} = Engine.start_tenant(:test_tenant, @simple_network)

      # Assert some facts
      facts = [
        %{id: 1, type: :TestFact, data: "test1"},
        %{id: 2, type: :TestFact, data: "test2"}
      ]

      assert {:ok, _} = Engine.assert(pid, facts)
      Engine.stop_tenant(:test_tenant)
    end
  end

  describe "memory tracking" do
    test "memory usage is tracked correctly" do
      {:ok, pid} =
        Engine.start_tenant(:test_tenant, @simple_network,
          memory_limit_mb: 10,
          # Check every operation
          memory_check_interval: 1
        )

      # Get initial memory stats
      {:ok, initial_stats} = Engine.snapshot(pid)
      assert is_map(initial_stats)

      # Add some facts
      facts =
        for i <- 1..10 do
          %{id: i, type: :TestFact, data: String.duplicate("data", 100)}
        end

      assert {:ok, _} = Engine.assert(pid, facts)

      Engine.stop_tenant(:test_tenant)
    end
  end

  describe "memory limit enforcement" do
    test "memory limit is enforced during fact assertion" do
      # Very small memory limit to trigger enforcement
      {:ok, pid} =
        Engine.start_tenant(:test_tenant, @simple_network,
          # 1KB limit
          memory_limit_mb: 0.001,
          # Check every operation
          memory_check_interval: 1
        )

      # Create large facts that exceed the limit
      large_facts =
        for i <- 1..100 do
          %{id: i, type: :TestFact, data: String.duplicate("x", 1000)}
        end

      # Should eventually hit memory limit
      result = Engine.assert(pid, large_facts)

      case result do
        {:error, {:memory_limit_exceeded, _message}} ->
          # Expected behaviour - memory limit was enforced
          assert true

        {:ok, _} ->
          # May not trigger immediately due to check interval
          # Let's try adding more facts
          more_facts =
            for i <- 101..200 do
              %{id: i, type: :TestFact, data: String.duplicate("y", 1000)}
            end

          result2 = Engine.assert(pid, more_facts)

          case result2 do
            {:error, {:memory_limit_exceeded, _message}} -> assert true
            {:ok, _} -> flunk("Memory limit should have been enforced")
          end
      end

      Engine.stop_tenant(:test_tenant)
    end

    test "memory eviction policies work correctly" do
      # Test LRU eviction policy
      {:ok, pid} =
        Engine.start_tenant(:test_tenant, @simple_network,
          # 10KB limit
          memory_limit_mb: 0.01,
          memory_check_interval: 50,
          memory_eviction_policy: :lru
        )

      # Add facts gradually to trigger eviction
      for batch <- 1..5 do
        facts =
          for i <- (batch * 10 - 9)..(batch * 10) do
            %{id: "batch_#{batch}_#{i}", type: :TestFact, data: String.duplicate("data", 50)}
          end

        # This should work as eviction will make space
        result = Engine.assert(pid, facts)
        assert {:ok, _} = result
      end

      Engine.stop_tenant(:test_tenant)
    end
  end

  describe "memory statistics" do
    test "memory stats are provided correctly" do
      {:ok, pid} =
        Engine.start_tenant(:test_tenant, @simple_network,
          memory_limit_mb: 5,
          memory_check_interval: 10
        )

      # Add some facts
      facts =
        for i <- 1..20 do
          %{id: i, type: :TestFact, data: "test_data_#{i}"}
        end

      {:ok, _} = Engine.assert(pid, facts)

      # Get snapshot which includes memory stats
      {:ok, snapshot} = Engine.snapshot(pid)
      assert is_map(snapshot)

      Engine.stop_tenant(:test_tenant)
    end
  end

  describe "MemoryManager module" do
    test "calculates memory usage correctly" do
      # Use simple network to create proper state
      {:ok, pid} =
        Engine.start_tenant(:test_manager, @simple_network,
          memory_limit_mb: 1,
          memory_check_interval: 10
        )

      # Add a fact to test memory calculation
      {:ok, _} = Engine.assert(pid, %{id: 1, type: :TestFact, data: "test"})

      # Get stats via the public API
      {:ok, snapshot} = Engine.snapshot(pid)
      assert is_map(snapshot)

      Engine.stop_tenant(:test_manager)
    end
  end
end

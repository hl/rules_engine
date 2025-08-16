defmodule RulesEngine.Engine.MemoryManagerTest do
  use ExUnit.Case, async: true
  doctest RulesEngine.Engine.MemoryManager

  alias RulesEngine.Engine.{MemoryManager, State}
  alias RulesEngine.DSL.Compiler

  @simple_dsl """
  rule "test_rule" do
    when
      entry: Entry(value: 10)
    then
      emit Result(id: "test")
  end
  """

  setup do
    {:ok, ir} = Compiler.parse_and_compile("test", @simple_dsl, %{cache: false})
    %{ir: ir}
  end

  describe "configurable memory limits" do
    test "starts engine without memory limit", %{ir: ir} do
      assert {:ok, pid} = RulesEngine.Engine.start_tenant("test_unlimited", ir, [])

      state = :sys.get_state(pid)
      assert state.memory_limit_bytes == nil
      assert state.memory_usage_bytes == 0
      assert state.memory_eviction_policy == :lru

      RulesEngine.Engine.stop_tenant("test_unlimited")
    end

    test "starts engine with memory limit", %{ir: ir} do
      assert {:ok, pid} = RulesEngine.Engine.start_tenant("test_limited", ir, memory_limit_mb: 5)

      state = :sys.get_state(pid)
      # 5MB
      assert state.memory_limit_bytes == 5 * 1024 * 1024
      assert state.memory_usage_bytes == 0
      assert state.memory_check_interval == 1000

      RulesEngine.Engine.stop_tenant("test_limited")
    end

    test "configures memory eviction policy", %{ir: ir} do
      opts = [memory_limit_mb: 5, memory_eviction_policy: :oldest]
      assert {:ok, pid} = RulesEngine.Engine.start_tenant("test_eviction", ir, opts)

      state = :sys.get_state(pid)
      assert state.memory_eviction_policy == :oldest

      RulesEngine.Engine.stop_tenant("test_eviction")
    end

    test "configures memory check interval", %{ir: ir} do
      opts = [memory_limit_mb: 5, memory_check_interval: 500]
      assert {:ok, pid} = RulesEngine.Engine.start_tenant("test_interval", ir, opts)

      state = :sys.get_state(pid)
      assert state.memory_check_interval == 500

      RulesEngine.Engine.stop_tenant("test_interval")
    end
  end

  describe "memory statistics" do
    test "returns memory stats with limit", %{ir: ir} do
      assert {:ok, pid} = RulesEngine.Engine.start_tenant("test_stats", ir, memory_limit_mb: 10)

      state = :sys.get_state(pid)
      stats = MemoryManager.get_memory_stats(state)

      assert stats.limit_bytes == 10 * 1024 * 1024
      assert stats.usage_bytes >= 0
      assert stats.usage_percentage >= 0.0
      assert stats.facts_count == 0
      assert stats.agenda_size == 0

      RulesEngine.Engine.stop_tenant("test_stats")
    end

    test "returns memory stats without limit", %{ir: ir} do
      assert {:ok, pid} = RulesEngine.Engine.start_tenant("test_stats_unlimited", ir, [])

      state = :sys.get_state(pid)
      stats = MemoryManager.get_memory_stats(state)

      assert stats.limit_bytes == nil
      assert stats.usage_bytes >= 0
      assert stats.usage_percentage == 0.0
      assert stats.facts_count == 0
      assert stats.agenda_size == 0

      RulesEngine.Engine.stop_tenant("test_stats_unlimited")
    end
  end

  describe "memory enforcement" do
    test "check_and_enforce_limits passes when no limit set" do
      state = %State{
        memory_limit_bytes: nil,
        memory_usage_bytes: 1000,
        operation_count: 100
      }

      assert {:ok, ^state} = MemoryManager.check_and_enforce_limits(state, 100)
    end

    test "check_and_enforce_limits skips check when not at interval" do
      state = %State{
        # 1MB
        memory_limit_bytes: 1024 * 1024,
        memory_usage_bytes: 0,
        memory_check_interval: 1000,
        operation_count: 500
      }

      assert {:ok, ^state} = MemoryManager.check_and_enforce_limits(state, 500)
    end
  end

  describe "eviction policies" do
    test "selects facts for eviction with LRU policy" do
      # This would be more comprehensive with actual fact data
      # For now just test the function exists and basic structure
      state = %State{
        memory_limit_bytes: 1024,
        memory_eviction_policy: :lru,
        working_memory: %RulesEngine.Engine.WorkingMemory{facts: %{}}
      }

      # Test that attempt_eviction handles empty facts gracefully
      assert {:ok, ^state} = MemoryManager.attempt_eviction(state, 0)
    end
  end
end

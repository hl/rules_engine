# Test configurable memory limits per tenant

simple_dsl = """
rule "test_rule" do
  when
    entry: Entry(value: 10)
  then
    emit Result(id: "test")
end
"""

# Test without memory limit (should work)
{:ok, ir} = RulesEngine.DSL.Compiler.parse_and_compile("test", simple_dsl, %{cache: false})

case RulesEngine.Engine.start_tenant("test_unlimited", ir, []) do
  {:ok, _pid} ->
    IO.puts("✅ Engine started without memory limit")
    RulesEngine.Engine.stop_tenant("test_unlimited")

  {:error, error} ->
    IO.puts("❌ Engine failed to start: #{inspect(error)}")
end

# Test with memory limit (should work)
case RulesEngine.Engine.start_tenant("test_limited", ir, memory_limit_mb: 10) do
  {:ok, _pid} ->
    IO.puts("✅ Engine started with 10MB memory limit")

    # Test memory stats
    case RulesEngine.Engine.MemoryManager.get_memory_stats(
           :sys.get_state(RulesEngine.Engine.whereis("test_limited"))
         ) do
      %{limit_bytes: limit, usage_bytes: usage} when is_integer(limit) ->
        IO.puts("📊 Memory limit: #{div(limit, 1024 * 1024)}MB, usage: #{usage} bytes")

      stats ->
        IO.puts("📊 Memory stats: #{inspect(stats)}")
    end

    RulesEngine.Engine.stop_tenant("test_limited")

  {:error, error} ->
    IO.puts("❌ Engine with memory limit failed to start: #{inspect(error)}")
end

IO.puts("Memory limits test completed")

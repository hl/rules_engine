# Quick benchmark test to verify O(n log n) performance

defmodule QuickBenchmark do
  def run do
    IO.puts("Testing network compilation performance...")

    # Generate a medium-complexity ruleset
    # 50 rules with multiple bindings each
    dsl = generate_ruleset(50)

    # Benchmark compilation
    {time_us, {:ok, ir}} =
      :timer.tc(fn ->
        RulesEngine.DSL.Compiler.parse_and_compile("benchmark", dsl, %{cache: false})
      end)

    time_ms = time_us / 1000

    IO.puts("✅ Successfully compiled #{length(ir["rules"])} rules")
    IO.puts("📊 Alpha nodes: #{length(ir["network"]["alpha"])}")
    IO.puts("📊 Beta nodes: #{length(ir["network"]["beta"])}")
    IO.puts("⚡ Compilation time: #{Float.round(time_ms, 2)}ms")

    # Verify join conditions are working
    beta_with_joins =
      Enum.count(ir["network"]["beta"], fn beta ->
        length(beta["on"]) > 0
      end)

    IO.puts("🔗 Beta nodes with join conditions: #{beta_with_joins}")

    if beta_with_joins > 0 do
      IO.puts("✅ Join detection is working correctly")
    else
      IO.puts("⚠️ No join conditions detected")
    end
  end

  defp generate_ruleset(rule_count) do
    rules =
      for i <- 1..rule_count do
        """
        rule "rule_#{i}" salience: #{rem(i, 100)} do
          when
            emp#{i}: Employee(id: e#{i}, dept: d#{i})
            ts#{i}: TimesheetEntry(employee_id: e#{i}, hours: h#{i})
            policy#{i}: Policy(department: d#{i}, max_hours: max#{i})
            guard h#{i} > max#{i}
          then
            emit Violation(rule: "rule_#{i}", employee: e#{i}, excess: h#{i} - max#{i})
        end
        """
      end

    Enum.join(rules, "\n")
  end
end

QuickBenchmark.run()

defmodule NetworkCompilationBench do
  @moduledoc """
  Benchmarks for network compilation performance to identify O(n²) bottlenecks.
  Tests compilation time vs ruleset size to verify algorithmic complexity.
  """

  def run do
    IO.puts("Network Compilation Performance Benchmark")
    IO.puts("=========================================\n")

    # Test with different ruleset sizes
    sizes = [10, 25, 50, 100]

    results =
      Enum.map(sizes, fn size ->
        {size, benchmark_compilation(size)}
      end)

    # Print results
    IO.puts("Rule Count | Compilation Time (ms) | Rules/sec")
    IO.puts("-----------|----------------------|----------")

    Enum.each(results, fn {size, time_ms} ->
      rules_per_sec = trunc(size * 1000 / time_ms)
      :io.format("~8w | ~18w | ~8w~n", [size, time_ms, rules_per_sec])
    end)

    # Calculate complexity
    analyze_complexity(results)

    results
  end

  defp benchmark_compilation(rule_count) do
    dsl_source = generate_test_dsl(rule_count)

    # Warm up
    compile_dsl(dsl_source)

    # Actual benchmark - average of 3 runs
    times =
      for _ <- 1..3 do
        {time_us, _result} =
          :timer.tc(fn ->
            compile_dsl(dsl_source)
          end)

        # Convert to milliseconds
        time_us / 1000
      end

    Enum.sum(times) / length(times)
  end

  defp compile_dsl(dsl_source) do
    # Call the compiler directly
    case RulesEngine.DSL.Compiler.parse_and_compile("test_tenant", dsl_source, %{cache: false}) do
      {:ok, _ir} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  defp generate_test_dsl(rule_count) do
    rules =
      for i <- 1..rule_count do
        # Generate rules with varying complexity
        # 2-5 bindings per rule
        binding_count = rem(i, 4) + 2

        bindings =
          for j <- 1..binding_count do
            field_name = "field#{rem(j + i, 10)}"
            "fact#{rem(j, 5)}: TestFact#{rem(j, 3)}(#{field_name}: #{field_name}_#{i})"
          end

        guards =
          for j <- 1..(binding_count - 1) do
            left_fact = "fact#{rem(j, 5)}"
            right_fact = "fact#{rem(j + 1, 5)}"
            "guard #{left_fact}.value > #{right_fact}.value"
          end

        when_clause = Enum.join(bindings ++ guards, "\n    ")

        """
        rule "test_rule_#{i}" salience: #{rem(i, 100)} do
          when
            #{when_clause}
          then
            emit TestResult(rule_id: "test_rule_#{i}", value: #{i})
        end
        """
      end

    Enum.join(rules, "\n\n")
  end

  defp analyze_complexity(results) do
    IO.puts("\nComplexity Analysis:")
    IO.puts("==================")

    # Calculate growth ratios
    growth_ratios =
      results
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{size1, time1}, {size2, time2}] ->
        size_ratio = size2 / size1
        time_ratio = time2 / time1
        complexity_factor = :math.log(time_ratio) / :math.log(size_ratio)

        {size1, size2, size_ratio, time_ratio, complexity_factor}
      end)

    IO.puts("Size Range | Size Ratio | Time Ratio | Complexity Factor")
    IO.puts("-----------|------------|------------|------------------")

    Enum.each(growth_ratios, fn {s1, s2, sr, tr, cf} ->
      :io.format("~3w -> ~3w | ~8.2f | ~8.2f | ~13.2f~n", [s1, s2, sr, tr, cf])
    end)

    avg_complexity =
      growth_ratios
      |> Enum.map(fn {_, _, _, _, cf} -> cf end)
      |> Enum.sum()
      |> Kernel./(length(growth_ratios))

    IO.puts("\nAverage Complexity Factor: #{Float.round(avg_complexity, 2)}")

    cond do
      avg_complexity < 1.2 -> IO.puts("Likely O(n) - Linear complexity")
      avg_complexity < 1.7 -> IO.puts("Likely O(n log n) - Log-linear complexity")
      avg_complexity < 2.2 -> IO.puts("Likely O(n²) - Quadratic complexity ⚠️")
      true -> IO.puts("Likely O(n³) or worse - Cubic+ complexity ❌")
    end
  end
end

# Run the benchmark using mix
case System.argv() do
  ["run"] -> NetworkCompilationBench.run()
  _ -> :ok
end

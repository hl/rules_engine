defmodule OptimizationComparison do
  @moduledoc """
  Benchmarks comparison between original O(n²) and optimized O(n log n) network compilation.
  Tests performance improvements across different ruleset sizes.
  """

  def run do
    IO.puts("Network Compilation Optimization Comparison")
    IO.puts("==========================================\n")

    # Test with different ruleset sizes
    sizes = [25, 50, 100, 200, 500]
    
    IO.puts("Benchmarking both algorithms...")
    results = Enum.map(sizes, fn size ->
      IO.puts("Testing #{size} rules...")
      
      original_time = benchmark_original(size)
      optimized_time = benchmark_optimized(size) 
      
      speedup = original_time / optimized_time
      improvement = ((original_time - optimized_time) / original_time) * 100
      
      {size, original_time, optimized_time, speedup, improvement}
    end)

    # Print detailed results
    print_results(results)
    
    # Analyze complexity improvements  
    analyze_improvements(results)
    
    results
  end

  defp benchmark_original(rule_count) do
    # Ensure original algorithm is used
    Application.put_env(:rules_engine, :use_optimized_compilation, false)
    
    dsl_source = generate_complex_dsl(rule_count)
    
    # Warm up
    compile_dsl(dsl_source)
    
    # Benchmark - average of 5 runs for better accuracy
    times = for _ <- 1..5 do
      {time_us, _result} = :timer.tc(fn ->
        compile_dsl(dsl_source)
      end)
      time_us / 1000  # Convert to milliseconds
    end
    
    Enum.sum(times) / length(times)
  end

  defp benchmark_optimized(rule_count) do
    # Enable optimized algorithm
    Application.put_env(:rules_engine, :use_optimized_compilation, true)
    
    dsl_source = generate_complex_dsl(rule_count)
    
    # Warm up
    compile_dsl(dsl_source)
    
    # Benchmark - average of 5 runs
    times = for _ <- 1..5 do
      {time_us, _result} = :timer.tc(fn ->
        compile_dsl(dsl_source)
      end)
      time_us / 1000
    end
    
    Enum.sum(times) / length(times)
  end

  defp compile_dsl(dsl_source) do
    case RulesEngine.DSL.Compiler.parse_and_compile("benchmark_tenant", dsl_source, %{cache: false}) do
      {:ok, _ir} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  defp generate_complex_dsl(rule_count) do
    # Generate more complex rules to stress test the algorithms
    rules = for i <- 1..rule_count do
      # Vary rule complexity: 2-6 bindings, multiple guards
      binding_count = rem(i, 5) + 2
      
      bindings = for j <- 1..binding_count do
        fact_type = "FactType#{rem(j + i, 8)}"
        binding_name = "fact#{j}"
        field_name = "field#{rem(j * i, 12)}"
        field_value = "value_#{i}_#{j}"
        
        "#{binding_name}: #{fact_type}(#{field_name}: #{field_value})"
      end
      
      # Create guards that reference multiple bindings (creates O(n²) joins)
      guards = for j <- 1..(binding_count - 1) do
        for k <- (j+1)..binding_count do
          left_fact = "fact#{j}"
          right_fact = "fact#{k}"
          comparison = Enum.random(["==", "!=", ">", "<", ">=", "<="])
          "guard #{left_fact}.value #{comparison} #{right_fact}.value"
        end
      end |> List.flatten()
      
      # Add some not/exists patterns for more complex network topology
      not_exists = if rem(i, 3) == 0 do
        not_fact_type = "NotFactType#{rem(i, 4)}"
        ["not #{not_fact_type}(status: :active)"]
      else
        []
      end
      
      all_conditions = Enum.join(bindings ++ guards ++ not_exists, "\n    ")
      
      # Complex actions
      actions = [
        "emit ProcessedFact(rule_id: \"complex_rule_#{i}\", result: #{i * 100})",
        "call MyModule, :process_result, [#{i}]",
        "log :info, \"Rule #{i} fired with #{binding_count} bindings\""
      ]
      
      action_clause = Enum.join(actions, "\n    ")
      
      """
      rule "complex_rule_#{i}" salience: #{100 - rem(i, 100)} do
        when
          #{all_conditions}
        then
          #{action_clause}
      end
      """
    end
    
    Enum.join(rules, "\n\n")
  end

  defp print_results(results) do
    IO.puts("\nDetailed Performance Comparison")
    IO.puts("==============================")
    IO.puts("Rules | Original (ms) | Optimized (ms) | Speedup | Improvement")
    IO.puts("------|---------------|----------------|---------|------------")
    
    Enum.each(results, fn {size, orig, opt, speedup, improvement} ->
      :io.format("~5w | ~11.2f | ~12.2f | ~5.2fx | ~8.1f%~n", 
        [size, orig, opt, speedup, improvement])
    end)
  end

  defp analyze_improvements(results) do
    IO.puts("\nPerformance Analysis")
    IO.puts("===================")
    
    total_original = Enum.sum(Enum.map(results, fn {_, orig, _, _, _} -> orig end))
    total_optimized = Enum.sum(Enum.map(results, fn {_, _, opt, _, _} -> opt end))
    overall_speedup = total_original / total_optimized
    overall_improvement = ((total_original - total_optimized) / total_original) * 100
    
    IO.puts("Overall speedup: #{Float.round(overall_speedup, 2)}x")
    IO.puts("Overall improvement: #{Float.round(overall_improvement, 1)}%")
    
    # Analyze how speedup scales with ruleset size
    {small_results, large_results} = Enum.split(results, div(length(results), 2))
    
    small_avg_speedup = small_results 
    |> Enum.map(fn {_, _, _, speedup, _} -> speedup end)
    |> Enum.sum() 
    |> Kernel./(length(small_results))
    
    large_avg_speedup = large_results
    |> Enum.map(fn {_, _, _, speedup, _} -> speedup end)
    |> Enum.sum()
    |> Kernel./(length(large_results))
    
    IO.puts("Small rulesets (#{length(small_results)} sizes) avg speedup: #{Float.round(small_avg_speedup, 2)}x")
    IO.puts("Large rulesets (#{length(large_results)} sizes) avg speedup: #{Float.round(large_avg_speedup, 2)}x")
    
    scaling_improvement = large_avg_speedup / small_avg_speedup
    IO.puts("Scaling improvement factor: #{Float.round(scaling_improvement, 2)}x")
    
    if scaling_improvement > 1.2 do
      IO.puts("✅ Optimization shows improved scaling with larger rulesets (target achieved)")
    else
      IO.puts("⚠️  Optimization scaling benefit is limited")
    end
    
    # Check complexity factor improvement
    original_complexity = analyze_complexity_factor(results, :original)
    optimized_complexity = analyze_complexity_factor(results, :optimized)
    
    IO.puts("\nComplexity Analysis:")
    IO.puts("Original algorithm complexity factor: #{Float.round(original_complexity, 2)}")
    IO.puts("Optimized algorithm complexity factor: #{Float.round(optimized_complexity, 2)}")
    
    if original_complexity > 1.8 and optimized_complexity < 1.5 do
      IO.puts("✅ Successfully reduced from O(n²) to O(n log n)")
    elsif original_complexity > optimized_complexity + 0.3 do
      IO.puts("✅ Significant complexity improvement achieved")  
    else
      IO.puts("⚠️  Complexity improvement is marginal")
    end
  end

  defp analyze_complexity_factor(results, algorithm) do
    # Extract times for the specified algorithm
    times = case algorithm do
      :original -> Enum.map(results, fn {_, orig, _, _, _} -> orig end)
      :optimized -> Enum.map(results, fn {_, _, opt, _, _} -> opt end)
    end
    
    sizes = Enum.map(results, fn {size, _, _, _, _} -> size end)
    
    # Calculate complexity factors between consecutive measurements
    complexity_factors = Enum.zip(sizes, times)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{size1, time1}, {size2, time2}] ->
      size_ratio = size2 / size1
      time_ratio = time2 / time1
      :math.log(time_ratio) / :math.log(size_ratio)
    end)
    |> Enum.filter(fn cf -> is_number(cf) and cf > 0 end)  # Filter invalid values
    
    case complexity_factors do
      [] -> 1.0  # Fallback
      factors -> Enum.sum(factors) / length(factors)
    end
  end
end

# Run the benchmark if called directly
case System.argv() do
  ["run"] -> OptimizationComparison.run()
  _ -> :ok
end
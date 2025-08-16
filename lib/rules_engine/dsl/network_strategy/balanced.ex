defmodule RulesEngine.DSL.NetworkStrategy.Balanced do
  @moduledoc """
  Balanced network building strategy with moderate optimization.

  This strategy provides a balance between compilation speed and runtime
  performance using proven O(n log n) algorithms with selective optimization.
  Ideal for most production use cases where both compilation and runtime
  performance matter.

  ## Optimization Approach

  **Alpha Network:**
  - Single-level indexing with selectivity analysis
  - Hash tables for high-selectivity equality constraints
  - B-trees for range and comparison operations
  - Constraint reordering based on simple heuristics

  **Beta Network:**
  - Heuristic-based join ordering
  - Basic selectivity estimation
  - Common constraint sharing
  - Limited bloom filter usage

  **Accumulate Network:**
  - Basic incremental updates for simple aggregations
  - Group-by optimization for common patterns
  - Delta propagation for count/sum operations

  ## Trade-offs

  **Benefits:**
  - Good compilation speed (O(n log n))
  - Good runtime performance for most workloads
  - Predictable behavior and resource usage
  - Moderate memory consumption

  **Costs:**
  - Not optimal for extreme performance requirements
  - Limited optimization for complex join patterns
  - Heuristic-based rather than cost-based optimization

  ## Performance Characteristics

  - **Compilation**: O(n log n) complexity
  - **Runtime**: Good for small to large rulesets
  - **Memory**: Balanced compilation and runtime memory usage
  - **Optimization Level**: Selective heuristic optimization

  ## Use Cases

  ```elixir
  # Default balanced strategy
  config :rules_engine, :network_strategy, RulesEngine.DSL.NetworkStrategy.Balanced

  # Most applications should use balanced strategy
  RulesEngine.DSL.Compiler.compile(tenant, ast, %{
    network_strategy: RulesEngine.DSL.NetworkStrategy.Balanced
  })
  ```

  This strategy is the recommended default for most applications as it provides
  the best balance of compilation speed, runtime performance, and predictability.
  """

  @behaviour RulesEngine.DSL.NetworkStrategy

  alias RulesEngine.Engine.PredicateRegistry

  @impl true
  def strategy_name, do: :balanced

  @impl true
  def build_alpha_network(rules, opts) do
    # O(n log n) balanced alpha network with selective optimization
    rules
    |> extract_fact_patterns_efficiently(opts)
    |> analyze_basic_selectivity()
    |> build_selective_indices()
    |> reorder_constraints_heuristic()
    |> build_balanced_alpha_nodes()
  end

  @impl true
  def build_beta_network(rules, _opts) do
    # O(n log n) heuristic join optimization
    binding_stats = analyze_binding_statistics(rules)

    rules
    |> Enum.with_index()
    |> Enum.flat_map(&build_balanced_rule_joins(&1, binding_stats))
    |> apply_heuristic_join_ordering()
    |> add_selective_bloom_filters()
  end

  @impl true
  def build_accumulate_network(rules, _opts) do
    # O(n log n) balanced accumulate processing
    rules
    |> extract_accumulate_statements()
    |> classify_accumulate_patterns()
    |> build_selective_incremental_structures()
    |> optimize_common_group_by_patterns()
  end

  @impl true
  def compilation_complexity do
    %{
      alpha: "O(n log n) - selective indexing",
      beta: "O(n log n) - heuristic optimization",
      accumulate: "O(n log n) - pattern-based optimization",
      overall: "O(n log n)"
    }
  end

  @impl true
  def runtime_performance do
    %{
      fact_insertion: "O(log m) - indexed when beneficial",
      rule_evaluation: "O(n log m) - good selectivity",
      join_performance: "O(n log m) - heuristic ordering",
      memory_usage: "Moderate - selective sharing"
    }
  end

  # Private implementation

  defp extract_fact_patterns_efficiently(rules, opts) do
    fact_schemas = Map.get(opts, :fact_schemas, %{})

    rules
    |> Enum.flat_map(&extract_rule_patterns(&1, fact_schemas))
    |> add_basic_statistics(fact_schemas)
  end

  defp extract_rule_patterns(rule, schemas) do
    (rule["bindings"] || [])
    |> Enum.map(fn binding ->
      fact_type = binding["type"]
      schema = Map.get(schemas, fact_type, %{})

      %{
        type: fact_type,
        binding: binding["name"],
        constraints: extract_constraints(binding["fields"] || []),
        rule_index: rule["index"],
        estimated_size: estimate_fact_size(fact_type, schemas),
        schema: schema
      }
    end)
  end

  defp extract_constraints(fields) do
    Enum.map(fields, fn field ->
      %{
        field: field["name"],
        op: field["op"] || "==",
        value: field["value"],
        type: infer_field_type(field["value"])
      }
    end)
  end

  defp add_basic_statistics(patterns, _schemas) do
    Enum.map(patterns, fn pattern ->
      selectivity_stats =
        Enum.map(pattern.constraints, fn constraint ->
          %{
            constraint
            | selectivity: estimate_constraint_selectivity(constraint),
              indexable: constraint_indexable?(constraint)
          }
        end)

      %{
        pattern
        | constraints: selectivity_stats,
          overall_selectivity: calculate_pattern_selectivity(selectivity_stats)
      }
    end)
  end

  defp analyze_basic_selectivity(patterns) do
    # Use predicate registry for known operations
    Enum.map(patterns, fn pattern ->
      enhanced_constraints =
        Enum.map(pattern.constraints, fn constraint ->
          op_atom = String.to_atom(constraint.op)

          selectivity =
            if PredicateRegistry.supported?(op_atom) do
              # Use registry selectivity hint
              PredicateRegistry.selectivity_hint(op_atom)
            else
              # Fall back to heuristic
              constraint.selectivity
            end

          %{constraint | selectivity: selectivity}
        end)

      %{pattern | constraints: enhanced_constraints}
    end)
  end

  defp build_selective_indices(patterns) do
    # Build indices only where they provide significant benefit
    patterns_by_type = Enum.group_by(patterns, & &1.type)

    Enum.map(patterns_by_type, fn {fact_type, type_patterns} ->
      all_constraints = Enum.flat_map(type_patterns, & &1.constraints)

      # Only build indices for highly selective constraints
      beneficial_indices =
        all_constraints
        |> Enum.filter(&should_index_constraint?/1)
        # Limit indices to avoid overhead
        |> Enum.take(3)
        |> Enum.map(&build_appropriate_index/1)

      %{
        fact_type: fact_type,
        patterns: type_patterns,
        indices: beneficial_indices
      }
    end)
  end

  defp should_index_constraint?(constraint) do
    # Index if highly selective or frequently used operation
    constraint.selectivity < 0.3 and constraint_indexable?(constraint)
  end

  defp build_appropriate_index(constraint) do
    # Choose index type based on operation and selectivity
    case constraint.op do
      "==" when constraint.selectivity < 0.1 ->
        %{type: "hash", field: constraint.field, selectivity: constraint.selectivity}

      op when op in ["<", ">", "<=", ">=", "between"] ->
        %{type: "btree", field: constraint.field, selectivity: constraint.selectivity}

      _ ->
        %{type: "btree", field: constraint.field, selectivity: constraint.selectivity}
    end
  end

  defp reorder_constraints_heuristic(indexed_patterns) do
    # Simple heuristic: order by selectivity
    Enum.map(indexed_patterns, fn pattern_group ->
      reordered_patterns =
        Enum.map(pattern_group.patterns, fn pattern ->
          reordered_constraints =
            Enum.sort_by(pattern.constraints, & &1.selectivity)

          %{pattern | constraints: reordered_constraints}
        end)

      %{pattern_group | patterns: reordered_patterns}
    end)
  end

  defp build_balanced_alpha_nodes(indexed_patterns) do
    Enum.map(indexed_patterns, fn %{fact_type: fact_type, patterns: patterns, indices: indices} ->
      %{
        "id" => "alpha_#{fact_type}",
        "type" => "fact",
        "fact_type" => fact_type,
        "pattern_count" => length(patterns),
        "indices" => indices,
        "selectivity" => calculate_alpha_selectivity(patterns),
        "optimization" => "balanced"
      }
    end)
  end

  defp analyze_binding_statistics(rules) do
    # Simple binding usage analysis for join ordering
    all_bindings =
      rules
      |> Enum.flat_map(&extract_rule_bindings/1)
      |> Enum.group_by(& &1.name)

    Map.new(all_bindings, fn {binding, usages} ->
      {binding,
       %{
         frequency: length(usages),
         avg_selectivity: calculate_avg_selectivity(usages)
       }}
    end)
  end

  defp build_balanced_rule_joins({rule, index}, binding_stats) do
    whens = rule["when"] || []

    # Process guards and fact joins with moderate optimization
    guards = extract_guard_joins(whens, index, binding_stats)
    facts = extract_fact_joins(whens, index, binding_stats)

    guards ++ facts
  end

  defp extract_guard_joins(whens, rule_index, binding_stats) do
    whens
    |> Enum.filter(&match?(%{"guard" => _}, &1))
    |> Enum.map(&build_balanced_guard_join(&1, rule_index, binding_stats))
  end

  defp extract_fact_joins(whens, rule_index, _binding_stats) do
    whens
    |> Enum.filter(&match?(%{"fact" => _}, &1))
    |> Enum.map(&build_balanced_fact_join(&1, rule_index))
  end

  defp build_balanced_guard_join(guard_node, rule_index, binding_stats) do
    guard_expr = guard_node["guard"]

    %{
      "id" => "guard_join_#{rule_index}",
      "type" => "guard",
      "rule_index" => rule_index,
      "conditions" => flatten_guard_balanced(guard_expr),
      "estimated_cost" => estimate_guard_cost(guard_expr, binding_stats),
      "optimization" => "heuristic"
    }
  end

  defp build_balanced_fact_join(fact_node, rule_index) do
    fact = fact_node["fact"]

    %{
      "id" => "fact_join_#{rule_index}_#{fact["type"]}",
      "type" => "fact_join",
      "rule_index" => rule_index,
      "fact_type" => fact["type"],
      "binding" => fact["binding"],
      # Default heuristic
      "estimated_selectivity" => 0.5,
      "optimization" => "basic"
    }
  end

  defp apply_heuristic_join_ordering(joins) do
    # Simple heuristic: order by estimated cost/selectivity
    Enum.sort_by(joins, &Map.get(&1, "estimated_cost", 1.0))
  end

  defp add_selective_bloom_filters(joins) do
    # Add bloom filters only for expensive joins
    expensive_joins = Enum.filter(joins, &(Map.get(&1, "estimated_cost", 0.0) > 5.0))

    bloom_filters =
      expensive_joins
      # Limit bloom filters
      |> Enum.take(2)
      |> Enum.map(
        &%{
          "type" => "bloom_filter",
          "target_join" => &1["id"],
          "false_positive_rate" => 0.05
        }
      )

    joins ++ bloom_filters
  end

  # Helper functions with moderate complexity

  # Simple heuristic
  defp estimate_fact_size(_type, _schemas), do: 1000

  defp infer_field_type(value) do
    cond do
      is_number(value) -> "number"
      is_binary(value) -> "string"
      is_boolean(value) -> "boolean"
      true -> "unknown"
    end
  end

  defp estimate_constraint_selectivity(constraint) do
    # Simple heuristic based on operation type
    case constraint.op do
      "==" -> 0.1
      "!=" -> 0.9
      op when op in ["<", ">"] -> 0.5
      op when op in ["<=", ">="] -> 0.6
      "in" -> 0.3
      "between" -> 0.4
      _ -> 0.5
    end
  end

  defp constraint_indexable?(constraint) do
    constraint.op in ["==", "!=", "<", ">", "<=", ">=", "in", "between"]
  end

  defp calculate_pattern_selectivity(constraints) do
    # Combined selectivity using independence assumption
    Enum.reduce(constraints, 1.0, &(&2 * &1.selectivity))
  end

  defp calculate_alpha_selectivity(patterns) do
    patterns
    |> Enum.map(& &1.overall_selectivity)
    |> Enum.min(fn -> 1.0 end)
  end

  defp extract_rule_bindings(rule) do
    (rule["bindings"] || [])
    |> Enum.map(&%{name: &1["name"], type: &1["type"]})
  end

  defp calculate_avg_selectivity(usages) do
    if length(usages) > 0 do
      # Moderate selectivity heuristic
      0.3
    else
      1.0
    end
  end

  defp flatten_guard_balanced(guard_expr) do
    # Simplified guard flattening with basic optimization
    [
      %{
        "op" => "generic",
        "expr" => guard_expr,
        "estimated_cost" => 1.0
      }
    ]
  end

  defp estimate_guard_cost(_expr, _binding_stats), do: 1.0

  # Accumulate processing helpers
  defp extract_accumulate_statements(rules) do
    rules
    |> Enum.flat_map(&Map.get(&1, "_accumulates", []))
    |> Enum.with_index()
  end

  defp classify_accumulate_patterns(accumulates) do
    Enum.map(accumulates, fn {acc, index} ->
      pattern =
        case acc["reducer"] do
          "sum" -> :summation
          "count" -> :counting
          "avg" -> :averaging
          _ -> :complex
        end

      %{
        index: index,
        pattern: pattern,
        accumulate: acc,
        optimization_potential: pattern in [:summation, :counting]
      }
    end)
  end

  defp build_selective_incremental_structures(classified) do
    Enum.map(classified, fn acc ->
      incremental = acc.optimization_potential

      %{
        "id" => "accumulate_#{acc.index}",
        "type" => "accumulate",
        "pattern" => acc.pattern,
        "incremental" => incremental,
        "optimization" => if(incremental, do: "incremental", else: "basic")
      }
    end)
  end

  defp optimize_common_group_by_patterns(accumulates) do
    # Basic group-by optimization for common patterns
    accumulates
    |> Enum.map(fn acc ->
      has_group_by = Map.has_key?(acc.accumulate || %{}, "group_by")

      if has_group_by do
        Map.put(acc, "group_by_optimized", true)
      else
        acc
      end
    end)
  end
end

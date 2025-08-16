defmodule RulesEngine.DSL.NetworkStrategy.Fast do
  @moduledoc """
  Fast network building strategy optimized for compilation speed.

  This strategy prioritizes compilation speed over runtime performance by using
  simple O(n) algorithms with minimal optimization. Ideal for:

  - Development environments with frequent rule changes
  - Large rulesets where compilation time is critical
  - Testing scenarios with many compilation cycles
  - Applications where rule evaluation happens infrequently

  ## Trade-offs

  **Benefits:**
  - Very fast compilation (O(n) complexity)
  - Low memory usage during compilation
  - Simple, predictable behavior
  - Minimal compilation overhead

  **Costs:**
  - Suboptimal runtime performance
  - Higher memory usage during rule execution
  - No join optimization
  - Basic indexing only

  ## Performance Characteristics

  - **Compilation**: O(n) linear complexity
  - **Runtime**: Adequate for small to medium rulesets
  - **Memory**: Minimal compilation memory, higher runtime memory
  - **Optimization Level**: Basic fact grouping and simple joins

  ## Use Cases

  ```elixir
  # Configure globally
  config :rules_engine, :network_strategy, RulesEngine.DSL.NetworkStrategy.Fast

  # Or per compilation
  RulesEngine.DSL.Compiler.compile(tenant, ast, %{
    network_strategy: RulesEngine.DSL.NetworkStrategy.Fast
  })
  ```
  """

  @behaviour RulesEngine.DSL.NetworkStrategy

  @impl true
  def strategy_name, do: :fast_compilation

  @impl true
  def build_alpha_network(rules, _opts) do
    # O(n) simple alpha network - minimal optimization
    # Group facts by type without complex indexing
    rules
    |> extract_fact_patterns_simple()
    |> group_by_fact_type()
    |> build_basic_alpha_nodes()
    |> deduplicate_simple()
  end

  @impl true
  def build_beta_network(rules, _opts) do
    # O(n) simple beta network - no join optimization
    # Process guards in declaration order without reordering
    rules
    |> Enum.with_index()
    |> Enum.flat_map(&build_rule_joins_simple/1)
  end

  @impl true
  def build_accumulate_network(rules, _opts) do
    # O(n) simple accumulate processing
    # No incremental update optimization
    rules
    |> Enum.with_index()
    |> Enum.flat_map(&build_rule_accumulates_simple/1)
  end

  @impl true
  def compilation_complexity do
    %{
      alpha: "O(n)",
      beta: "O(n)",
      accumulate: "O(n)",
      overall: "O(n)"
    }
  end

  @impl true
  def runtime_performance do
    %{
      fact_insertion: "O(m) - linear scan",
      rule_evaluation: "O(n*m) - no optimization",
      join_performance: "O(n*m) - nested loops",
      memory_usage: "High - minimal sharing"
    }
  end

  # Private implementation

  defp extract_fact_patterns_simple(rules) do
    # Simple O(n) extraction without sophisticated analysis
    Enum.flat_map(rules, fn rule ->
      (rule["bindings"] || [])
      |> Enum.map(fn binding ->
        %{
          type: binding["type"],
          binding: binding["name"],
          fields: binding["fields"] || [],
          rule_index: rule["index"]
        }
      end)
    end)
  end

  defp group_by_fact_type(patterns) do
    # Simple grouping by fact type - O(n)
    Enum.group_by(patterns, & &1.type)
  end

  defp build_basic_alpha_nodes(grouped_patterns) do
    # Build one alpha node per fact type - O(n)
    Enum.map(grouped_patterns, fn {fact_type, patterns} ->
      %{
        "id" => "alpha_#{fact_type}",
        "type" => "fact",
        "fact_type" => fact_type,
        "patterns" => length(patterns),
        "optimization_level" => "basic",
        # Include all field constraints without selectivity analysis
        "constraints" => collect_all_constraints(patterns)
      }
    end)
  end

  defp deduplicate_simple(alpha_nodes) do
    # Simple deduplication by fact type - O(n)
    alpha_nodes
    |> Enum.uniq_by(& &1["fact_type"])
    |> Enum.sort_by(& &1["fact_type"])
  end

  defp collect_all_constraints(patterns) do
    # Collect all constraints without optimization
    patterns
    |> Enum.flat_map(fn pattern ->
      Enum.map(pattern.fields, fn field ->
        %{
          "field" => field["name"],
          "op" => field["op"] || "==",
          "value" => field["value"],
          # No selectivity analysis - use default
          "selectivity" => 0.5
        }
      end)
    end)
    |> Enum.uniq_by(&{&1["field"], &1["op"], &1["value"]})
  end

  defp build_rule_joins_simple({rule, index}) do
    # Simple join processing without optimization
    whens = rule["when"] || []

    # Convert guards to basic join nodes
    guard_joins =
      whens
      |> Enum.filter(&match?(%{"guard" => _}, &1))
      |> Enum.map(&build_guard_join_simple(&1, index))

    # Convert fact patterns to simple joins
    fact_joins =
      whens
      |> Enum.filter(&match?(%{"fact" => _}, &1))
      |> Enum.map(&build_fact_join_simple(&1, index))

    guard_joins ++ fact_joins
  end

  defp build_guard_join_simple(guard_node, rule_index) do
    guard_expr = guard_node["guard"]

    %{
      "id" => "join_rule_#{rule_index}_guard",
      "type" => "guard",
      "rule_index" => rule_index,
      "constraints" => flatten_guard_simple(guard_expr),
      "optimization" => "none"
    }
  end

  defp build_fact_join_simple(fact_node, rule_index) do
    fact = fact_node["fact"]

    %{
      "id" => "join_rule_#{rule_index}_fact_#{fact["type"]}",
      "type" => "fact_join",
      "rule_index" => rule_index,
      "fact_type" => fact["type"],
      "binding" => fact["binding"],
      "optimization" => "none"
    }
  end

  defp flatten_guard_simple(guard_expr) do
    # Simple guard flattening without optimization
    case guard_expr do
      %{"cmp" => %{"op" => op, "left" => left, "right" => right}} ->
        [
          %{
            "op" => op,
            "left" => term_simple(left),
            "right" => term_simple(right),
            # No cost estimation
            "cost" => 1.0
          }
        ]

      %{"and" => [a, b]} ->
        flatten_guard_simple(a) ++ flatten_guard_simple(b)

      %{"or" => [a, b]} ->
        flatten_guard_simple(a) ++ flatten_guard_simple(b)

      _ ->
        [
          %{
            "op" => "complex",
            "expr" => guard_expr,
            "cost" => 2.0
          }
        ]
    end
  end

  defp term_simple(term) do
    # Simple term processing without type inference
    case term do
      %{"binding" => binding, "field" => field} ->
        %{"type" => "binding", "binding" => binding, "field" => field}

      %{"literal" => value} ->
        %{"type" => "literal", "value" => value}

      _ ->
        %{"type" => "unknown", "value" => term}
    end
  end

  defp build_rule_accumulates_simple({rule, index}) do
    # Simple accumulate processing - no optimization
    accumulates = rule["_accumulates"] || []

    Enum.map(accumulates, fn acc ->
      %{
        "id" => "accumulate_rule_#{index}_#{acc["from"]}",
        "type" => "accumulate",
        "rule_index" => index,
        "from_pattern" => acc["from"],
        "reducer" => acc["reducer"],
        "group_by" => acc["group_by"],
        "having" => acc["having"],
        "optimization" => "none",
        # No incremental updates
        "incremental" => false
      }
    end)
  end
end

defmodule RulesEngine.DSL.NetworkStrategy do
  @moduledoc """
  Behaviour for configurable network building strategies.

  Allows host applications to choose between different compilation approaches
  that balance compilation speed vs runtime performance based on their needs.

  ## Strategy Types

  - **Fast Strategy**: Optimizes for compilation speed at the cost of runtime performance
  - **Optimized Strategy**: Optimizes for runtime performance at the cost of compilation time
  - **Balanced Strategy**: Provides a balance between compilation and runtime performance

  ## Usage

  Configure the strategy in your application:

      config :rules_engine, :network_strategy, RulesEngine.DSL.NetworkStrategy.Fast

  Or dynamically at compilation time:

      RulesEngine.DSL.Compiler.compile(tenant, ast, %{network_strategy: MyApp.CustomStrategy})

  ## Implementation

  Strategies implement this behaviour to provide custom network building algorithms.
  Each strategy receives the parsed AST and returns the same IR format but uses
  different algorithms for optimization trade-offs.

  ## Example Implementation

      defmodule MyApp.FastStrategy do
        @behaviour RulesEngine.DSL.NetworkStrategy
        
        @impl true
        def strategy_name, do: :my_fast_strategy
        
        @impl true
        def build_alpha_network(rules, _opts) do
          # Simple O(n) algorithm - fast compilation
          rules
          |> extract_fact_patterns()
          |> build_simple_alpha_nodes()
        end
        
        @impl true
        def build_beta_network(rules, _opts) do
          # Minimal join optimization
          build_basic_joins(rules)
        end
        
        @impl true
        def build_accumulate_network(rules, _opts) do
          # Basic accumulate handling
          build_simple_accumulates(rules)
        end
      end

  ## Performance Characteristics

  Different strategies provide different algorithmic complexities:

  - **Fast**: O(n) compilation, suboptimal runtime
  - **Optimized**: O(n log n) or O(n²) compilation, optimal runtime
  - **Balanced**: O(n log n) compilation, good runtime performance
  """

  @type rule :: map()
  @type rules :: [rule()]
  @type network :: map()
  @type opts :: map()

  @doc """
  Return unique strategy name for identification and configuration.

  Must return an atom that uniquely identifies this strategy.
  Used in configuration and logging.

  ## Examples

      def strategy_name, do: :fast_compilation
      def strategy_name, do: :runtime_optimized
  """
  @callback strategy_name() :: atom()

  @doc """
  Build alpha network from rules using this strategy's algorithms.

  The alpha network handles fact pattern matching and filtering.
  Different strategies can use different optimization levels:

  - Simple strategies: Basic fact type grouping
  - Optimized strategies: Advanced indexing, selectivity analysis
  - Balanced strategies: Moderate optimizations

  ## Arguments

  - `rules` - List of compiled rule maps with bindings and patterns
  - `opts` - Compilation options including fact schemas and configuration

  ## Returns

  Map containing alpha network nodes in IR format.
  """
  @callback build_alpha_network(rules(), opts()) :: network()

  @doc """
  Build beta network from rules using this strategy's algorithms.

  The beta network handles joins between fact patterns and guard conditions.
  Optimization strategies vary significantly:

  - Simple strategies: Basic join ordering
  - Optimized strategies: Cost-based optimization, selectivity estimation
  - Balanced strategies: Heuristic-based optimization

  ## Arguments

  - `rules` - List of compiled rule maps with guard expressions
  - `opts` - Compilation options and metadata

  ## Returns

  List of beta network join nodes in IR format.
  """
  @callback build_beta_network(rules(), opts()) :: [map()]

  @doc """
  Build accumulate network from rules using this strategy's algorithms.

  Handles aggregate operations like sum, count, group-by across facts.
  Strategies can optimize for different accumulation patterns:

  - Simple strategies: Basic accumulation without optimization
  - Optimized strategies: Incremental update optimization
  - Balanced strategies: Moderate incremental optimizations

  ## Arguments

  - `rules` - List of rules containing accumulate statements
  - `opts` - Compilation options and configuration

  ## Returns

  List of accumulate network nodes in IR format.
  """
  @callback build_accumulate_network(rules(), opts()) :: [map()]

  @doc """
  Estimate compilation complexity for this strategy.

  Returns algorithmic complexity information for benchmarking and selection.
  Used by the framework to help users choose appropriate strategies.

  ## Returns

  Map with complexity estimates:
  - `:alpha` - Alpha network complexity (e.g., "O(n)", "O(n log n)")
  - `:beta` - Beta network complexity  
  - `:accumulate` - Accumulate network complexity
  - `:overall` - Overall compilation complexity
  """
  @callback compilation_complexity() :: %{
              alpha: String.t(),
              beta: String.t(),
              accumulate: String.t(),
              overall: String.t()
            }

  @doc """
  Estimate runtime performance characteristics for this strategy.

  Returns performance information about the generated network for
  different workload patterns. Used for strategy selection guidance.

  ## Returns

  Map with performance characteristics:
  - `:fact_insertion` - Cost of inserting facts
  - `:rule_evaluation` - Cost of evaluating rules  
  - `:join_performance` - Cost of join operations
  - `:memory_usage` - Relative memory consumption
  """
  @callback runtime_performance() :: %{
              fact_insertion: String.t(),
              rule_evaluation: String.t(),
              join_performance: String.t(),
              memory_usage: String.t()
            }

  @optional_callbacks [
    compilation_complexity: 0,
    runtime_performance: 0
  ]

  @doc """
  Get the currently configured network strategy.
  """
  @spec get_strategy() :: module()
  def get_strategy do
    Application.get_env(
      :rules_engine,
      :network_strategy,
      RulesEngine.DSL.NetworkStrategy.Balanced
    )
  end

  @doc """
  Dynamically set the network strategy for testing or runtime configuration.
  """
  @spec set_strategy(module()) :: :ok
  def set_strategy(strategy) when is_atom(strategy) do
    Application.put_env(:rules_engine, :network_strategy, strategy)
    :ok
  end

  @doc """
  Build complete network using the configured strategy.
  """
  @spec build_network(rules(), opts()) :: map()
  def build_network(rules, opts \\ %{}) do
    strategy = Map.get(opts, :network_strategy, get_strategy())

    %{
      "alpha" => strategy.build_alpha_network(rules, opts),
      "beta" => strategy.build_beta_network(rules, opts),
      "accumulate" => strategy.build_accumulate_network(rules, opts)
    }
  end
end

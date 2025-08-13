# Codegen Modules

Compile-time generation of optimised Elixir modules from IR for maximum runtime performance.

## Goals

- Eliminate interpretation overhead during rule execution
- Generate type-safe, optimised Elixir code from validated IR
- Preserve debugging capabilities and traceability
- Enable compile-time optimisations (dead code elimination, constant folding)

## Architecture

### Code Generation Pipeline

1. **IR Analysis**: Analyse network topology, identify hot paths, collect optimisation hints
2. **Template Selection**: Choose appropriate templates based on node patterns
3. **Code Emission**: Generate Elixir modules with embedded network logic
4. **Compilation**: Compile generated modules with BEAM optimisations

### Generated Module Structure

```elixir
defmodule RulesEngine.Generated.Network_<hash> do
  @behaviour RulesEngine.Runtime.ExecutableNetwork
  
  # Network metadata
  @network_version "1.0.0"
  @node_count 42
  @selectivity_hints %{...}
  
  # Compiled memory structures
  @alpha_memories %{...}
  @beta_memories %{...}
  
  # Entry points
  def assert_fact(fact, context), do: ...
  def retract_fact(fact, context), do: ...
  def run_cycle(context), do: ...
end
```

## Core Types

### CodegenSpec
- target :: :beam | :native
- optimisation_level :: 0..3
- debug_info :: boolean
- inline_threshold :: integer
- template_overrides :: %{node_type => template_path}

### GeneratedModule
- module_name :: atom
- bytecode :: binary
- source_map :: %{line => ir_node_id}
- dependencies :: [atom]

## Code Templates

### Alpha Node Template
```elixir
def alpha_test_<node_id>(fact, context) do
  # Inline predicate tests
  case fact do
    %{type: "<type>", <field>: value} when value <op> <literal> ->
      store_in_alpha_memory(<memory_id>, fact, context)
    _ -> context
  end
end
```

### Join Node Template
```elixir
def join_<node_id>(left_tokens, right_wme, context) do
  # Hash-based join with inlined conditions
  left_index = Map.get(context.memories, <left_memory_id>)
  
  for left_token <- get_matching_tokens(left_index, right_wme.<join_field>),
      join_test_<node_id>(left_token, right_wme) do
    new_token = combine_tokens(left_token, right_wme)
    propagate_token(new_token, <next_nodes>, context)
  end
end

defp join_test_<node_id>(left_token, right_wme) do
  # Inline join conditions
  left_token.bindings.<var> == right_wme.<field>
end
```

### Production Template
```elixir
def production_<rule_id>(token, context) do
  # Inline RHS actions with conflict resolution
  case check_refraction(<rule_id>, token, context) do
    :fire ->
      context
      |> execute_action_<action_1>(token)
      |> execute_action_<action_2>(token)
      |> record_firing(<rule_id>, token)
    :skip -> context
  end
end
```

## Optimisations

### Compile-Time
- **Constant Folding**: Pre-evaluate constant expressions
- **Dead Code Elimination**: Remove unreachable nodes/conditions
- **Predicate Reordering**: Most selective predicates first
- **Template Specialisation**: Custom templates for common patterns

### Runtime
- **Inline Guards**: Convert predicates to pattern match guards
- **Hash Table Inlining**: Embed small lookup tables as case statements
- **Loop Unrolling**: Unroll small fixed-size iterations
- **Memory Layout**: Optimise token/fact layout for cache locality

## Debug Support

### Source Maps
- Map generated code lines to IR nodes
- Preserve variable names and rule identifiers
- Enable step-through debugging

### Instrumentation Hooks
```elixir
def alpha_test_<node_id>(fact, context) do
  context = maybe_trace(:alpha_enter, <node_id>, fact, context)
  # ... generated logic ...
  maybe_trace(:alpha_exit, <node_id>, result, context)
end
```

## Integration Points

### Compiler Interface
```elixir
defmodule RulesEngine.Codegen do
  @spec compile_network(IR.Network.t(), CodegenSpec.t()) :: 
    {:ok, GeneratedModule.t()} | {:error, term()}
  
  @spec load_module(GeneratedModule.t()) :: {:ok, atom()} | {:error, term()}
  
  @spec benchmark_vs_interpreter(IR.Network.t()) :: %{
    codegen_time: integer,
    interpreter_time: integer,
    speedup_factor: float
  }
end
```

### Runtime Compatibility
- Generated modules implement same behaviour as interpreter
- Seamless fallback to interpreter for debugging/development
- Hot code reloading support during development

## Performance Characteristics

### Expected Improvements
- **Alpha Tests**: 5-10x faster (pattern matching vs runtime dispatch)
- **Joins**: 3-5x faster (inlined hash lookups, specialised code)
- **Productions**: 2-3x faster (direct action execution)
- **Memory Overhead**: 10-20% reduction (compact token representation)

### Trade-offs
- **Compilation Time**: Adds 2-10s compile step per network
- **Code Size**: 2-5x larger than equivalent interpreter tables
- **Flexibility**: Generated code harder to modify at runtime

## Implementation Phases

### Phase 1: Basic Templates
- Alpha/beta node templates
- Simple predicate inlining
- Production action generation

### Phase 2: Optimisations
- Constant folding and dead code elimination
- Predicate reordering
- Memory layout optimisation

### Phase 3: Advanced Features
- Template specialisation
- Cross-node optimisation
- Performance profiling integration

## Configuration

### mix.exs Integration
```elixir
config :rules_engine, :codegen,
  enabled: true,
  optimisation_level: 2,
  cache_dir: "priv/compiled_networks",
  debug_info: Mix.env() != :prod
```

### Development Workflow
```bash
# Generate and benchmark
mix rules_engine.compile network.rule --codegen --benchmark

# Compare performance
mix rules_engine.profile network.rule --interpreter --codegen
```
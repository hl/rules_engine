# Advanced Predicate Operations

Extended predicate operations beyond equality and range comparisons for complex matching scenarios.

## Goals

- Support pattern matching, regular expressions, and custom predicates
- Maintain performance characteristics of existing operations
- Enable temporal, spatial, and domain-specific matching
- Preserve deterministic execution and indexing capabilities

## Current State

Existing predicates from `compiler_ir.md`:
- `:eq | :ne | :gt | :ge | :lt | :le` - scalar comparisons
- `:in | :not_in` - set membership
- `:between` - range inclusion
- `:overlap` - temporal window overlaps

## Extended Predicate Operations

### String/Pattern Operations
```elixir
- :matches         # regex match
- :starts_with     # string prefix
- :ends_with       # string suffix  
- :contains        # substring search
- :like            # SQL-style pattern (%, _)
- :ilike           # case-insensitive like
- :soundex         # phonetic matching
```

### Temporal Operations
```elixir
- :before          # timestamp comparison
- :after           # timestamp comparison
- :during          # within time period
- :overlaps        # time range overlap (enhanced)
- :adjacent        # touching time periods
- :within_duration # duration-based proximity
- :same_day        # date equality ignoring time
- :same_week       # week boundary matching
- :same_month      # month boundary matching
```

### Spatial/Geometric Operations
```elixir
- :within_distance # geometric proximity
- :within_bounds   # bounding box/polygon
- :intersects      # geometric intersection
- :touches         # geometric adjacency
- :contains_point  # point-in-polygon
```

### Collection Operations
```elixir
- :contains_all    # superset test
- :contains_any    # intersection test  
- :contains_none   # disjoint test
- :subset_of       # subset test
- :size_eq         # collection size
- :size_gt         # collection size comparison
- :empty           # empty collection test
- :all_match       # predicate over all elements
- :any_match       # predicate over any element
```

### Numeric/Statistical Operations
```elixir
- :approximately   # floating-point tolerance
- :multiple_of     # divisibility test
- :within_stddev   # statistical range
- :within_percent  # percentage-based range
- :prime           # prime number test
- :even            # even number test
- :odd             # odd number test
```

### Custom Predicate Operations
```elixir
- :custom          # user-defined predicate function
- :lambda          # inline anonymous function
```

## Enhanced Predicate Definition

### Extended Predicate Type
```elixir
defmodule IR.Predicate do
  @type operation :: 
    # Existing operations
    :eq | :ne | :gt | :ge | :lt | :le | :in | :not_in | :between | :overlap |
    
    # String operations
    :matches | :starts_with | :ends_with | :contains | :like | :ilike | :soundex |
    
    # Temporal operations  
    :before | :after | :during | :overlaps | :adjacent | :within_duration |
    :same_day | :same_week | :same_month |
    
    # Spatial operations
    :within_distance | :within_bounds | :intersects | :touches | :contains_point |
    
    # Collection operations
    :contains_all | :contains_any | :contains_none | :subset_of |
    :size_eq | :size_gt | :empty | :all_match | :any_match |
    
    # Numeric operations
    :approximately | :multiple_of | :within_stddev | :within_percent |
    :prime | :even | :odd |
    
    # Custom operations
    :custom | :lambda

  @type value ::
    # Existing value types
    literal | var | {from :: Expr.t(), to :: Expr.t()} |
    
    # Extended value types
    regex | duration | bounds | custom_function |
    tolerance_spec | statistical_spec

  @type t :: %__MODULE__{
    field: Path.t(),
    op: operation(),
    value: value(),
    options: keyword()  # Additional configuration
  }
end
```

### Value Type Extensions

#### Regex Support
```elixir
@type regex :: %{
  pattern: String.t(),
  flags: [:caseless | :multiline | :dotall | :extended]
}
```

#### Duration Specifications  
```elixir
@type duration :: %{
  amount: integer(),
  unit: :microseconds | :milliseconds | :seconds | :minutes | :hours | :days
}
```

#### Spatial Bounds
```elixir
@type bounds :: 
  %{type: :circle, center: {float(), float()}, radius: float()} |
  %{type: :rectangle, min: {float(), float()}, max: {float(), float()}} |  
  %{type: :polygon, points: [{float(), float()}]}
```

#### Tolerance Specifications
```elixir
@type tolerance_spec :: %{
  tolerance: float(),
  type: :absolute | :relative
}

@type statistical_spec :: %{
  standard_deviations: float(),
  baseline: :mean | :median | {value, float()}
}
```

#### Custom Functions
```elixir
@type custom_function :: %{
  module: atom(),
  function: atom(),
  arity: non_neg_integer(),
  args: [Expr.t()]  # Additional arguments beyond the field value
}
```

## DSL Extensions

### Regex Matching
```
Employee(name ~= /^John.*Smith$/i)
LogEntry(message ~= /ERROR.*database/m)
```

### Temporal Predicates
```
Shift(start_time before now() - 1.day)  
Event(timestamp during [start_time, end_time])
Appointment(time within 30.minutes of scheduled_time)
```

### Spatial Predicates  
```
Location(coordinates within_distance 5.km of warehouse_location)
Delivery(route intersects restricted_zone)
Store(location within_bounds london_borough)
```

### Collection Predicates
```
Order(items contains_all ["item1", "item2"])
User(permissions contains_any ["read", "write"]) 
Team(members size_gt 5)
Dataset(values all_match x -> x > 0)
```

### Statistical/Numeric Predicates
```
Measurement(value approximately 100.0 ± 0.1)
Account(balance within 2.stddev of account_average)
Inventory(count multiple_of 12)
```

### Custom Predicates
```
Person(age custom MyModule.is_adult/1)
Data(payload lambda x -> valid_json?(x) and x.version >= 2)
```

## Implementation Strategy

### Predicate Registry
```elixir
defmodule RulesEngine.Predicates do
  @callback evaluate(value :: term(), predicate_value :: term(), options :: keyword()) ::
    boolean()
    
  @callback indexable?() :: boolean()
  @callback selectivity_hint(predicate_value :: term()) :: float()
  
  def register_predicate(op :: atom(), module :: atom()) :: :ok
  def get_predicate_handler(op :: atom()) :: {:ok, atom()} | {:error, :not_found}
end
```

### Built-in Predicate Modules
```elixir
defmodule RulesEngine.Predicates.Regex do
  @behaviour RulesEngine.Predicates
  
  def evaluate(string_value, %{pattern: pattern, flags: flags}, _opts) do
    {:ok, regex} = Regex.compile(pattern, flags)
    Regex.match?(regex, to_string(string_value))
  end
  
  def indexable?, do: false  # Cannot efficiently index regex
  def selectivity_hint(_), do: 0.1  # Typically selective
end
```

### Index Strategy Extensions

#### Non-Indexable Predicates
- Store in separate evaluation list
- Evaluate after indexed predicates
- Consider bloom filters for common patterns

#### Partially Indexable Predicates
- Extract indexable components (e.g., prefix for `starts_with`)
- Use multi-stage filtering

#### Custom Index Types
- Spatial indexes (R-tree, Quad-tree)
- Text search indexes (inverted index, trigrams)
- Temporal indexes (interval trees)

## Performance Considerations

### Execution Order Optimisation
1. Indexed equality predicates (fastest)
2. Indexed range predicates  
3. Non-indexed simple predicates
4. Complex custom predicates (slowest)

### Caching Strategy
- Compile regex patterns at network build time
- Cache custom function results where deterministic
- Pre-compute spatial index structures

### Selectivity Estimation
```elixir
# Built-in selectivity hints
:eq -> 0.01          # Highly selective
:matches -> 0.05     # Regex typically selective
:contains -> 0.3     # Moderate selectivity
:custom -> 0.5       # Unknown, assume moderate
```

## Error Handling

### Predicate Validation
- Validate regex compilation at build time
- Check custom function existence and arity
- Validate spatial bounds and coordinate systems

### Runtime Error Recovery
```elixir
@type predicate_result :: 
  {:ok, boolean()} | 
  {:error, :invalid_value | :function_error | :timeout}
```

### Graceful Degradation
- Log predicate evaluation errors
- Configurable behavior: skip fact, fail rule, or default to false
- Circuit breaker for failing custom predicates

## Migration Path

### Phase 1: Core Extensions
- String operations (matches, starts_with, contains)
- Basic temporal operations (before, after, during)
- Collection operations (contains_all, size_eq)

### Phase 2: Advanced Operations  
- Spatial predicates with indexing
- Statistical operations
- Custom predicate framework

### Phase 3: Optimisation
- Advanced indexing strategies
- Query plan optimisation for complex predicates
- Performance profiling and tuning

## Configuration

### Network-Level Configuration
```elixir
%IR.Network{
  # ... existing fields ...
  predicate_config: %{
    regex_timeout_ms: 1000,
    custom_predicate_timeout_ms: 5000,
    spatial_index_type: :rtree,
    enable_predicate_caching: true
  }
}
```

### Global Configuration
```elixir
config :rules_engine, :predicates,
  registry_modules: [
    MyApp.CustomPredicates,
    RulesEngine.Predicates.Spatial,
    RulesEngine.Predicates.Text
  ],
  default_timeout: 1000,
  cache_size: 10_000
```
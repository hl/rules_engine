# Distributed Links

Network nodes that reference remote rule engines, enabling distributed rule execution across multiple processes or machines.

## Goals

- Enable horizontal scaling of rule networks across multiple nodes
- Support fact sharing and cross-network rule dependencies  
- Maintain consistency and ordering guarantees
- Provide fault tolerance and graceful degradation
- Preserve debugging and traceability across distributed execution

## Architecture Overview

### Distribution Model
- **Network Partitioning**: Split large networks across multiple engines
- **Fact Replication**: Share relevant facts between network partitions
- **Remote Node References**: Nodes that execute on remote engines
- **Coordination Protocol**: Ensure consistent execution ordering

### Core Components
1. **Link Manager**: Manages connections to remote engines
2. **Fact Synchroniser**: Handles fact replication and consistency
3. **Remote Proxy Nodes**: Local representations of remote nodes
4. **Coordination Service**: Manages distributed execution cycles
5. **Failure Detector**: Monitors remote engine health

## Extended IR Types

### Distributed Network
```elixir
%IR.Network{
  # ... existing fields ...
  cluster_id: String.t(),
  partition_id: String.t(), 
  remote_links: [RemoteLink.t()],
  fact_sync_config: FactSyncConfig.t(),
  coordination_mode: :centralized | :decentralized
}
```

### Remote Link
```elixir
defmodule IR.RemoteLink do
  @type t :: %__MODULE__{
    link_id: String.t(),
    target_engine: EngineRef.t(),
    node_mappings: %{local_node_id => remote_node_id},
    fact_filters: [FactFilter.t()],
    consistency_level: :eventual | :strong | :causal,
    retry_policy: RetryPolicy.t()
  }
end
```

### Engine Reference
```elixir
defmodule IR.EngineRef do
  @type t :: 
    %{type: :local_process, pid: pid()} |
    %{type: :named_process, name: atom()} |
    %{type: :distributed_node, node: atom(), name: atom()} |
    %{type: :http_endpoint, url: String.t(), auth: auth_spec()} |
    %{type: :message_queue, queue: String.t(), broker: broker_spec()}
end
```

### Fact Synchronisation
```elixir
defmodule IR.FactSyncConfig do  
  @type t :: %__MODULE__{
    sync_mode: :push | :pull | :bidirectional,
    batch_size: pos_integer(),
    sync_interval_ms: pos_integer(),
    conflict_resolution: :last_write_wins | :merge | :custom,
    vector_clock_enabled: boolean()
  }
end

defmodule IR.FactFilter do
  @type t :: %__MODULE__{
    fact_types: [String.t()],
    predicates: [IR.Predicate.t()],
    sync_direction: :inbound | :outbound | :bidirectional
  }
end
```

## Distribution Patterns

### Pattern 1: Network Partitioning
Split a large network across multiple engines based on fact types or rule groups.

```elixir
# Engine A: Customer processing rules
%IR.Network{
  partition_id: "customers",
  remote_links: [
    %RemoteLink{
      link_id: "to_orders", 
      target_engine: %{type: :distributed_node, node: :engine_b@host2},
      fact_filters: [
        %FactFilter{fact_types: ["OrderCreated"], sync_direction: :outbound}
      ]
    }
  ]
}

# Engine B: Order processing rules  
%IR.Network{
  partition_id: "orders",
  remote_links: [
    %RemoteLink{
      link_id: "to_customers",
      target_engine: %{type: :distributed_node, node: :engine_a@host1},
      fact_filters: [
        %FactFilter{fact_types: ["CustomerUpdated"], sync_direction: :inbound}
      ]
    }
  ]
}
```

### Pattern 2: Hierarchical Processing
Parent engines coordinate child engines for specialized processing.

```elixir
# Parent Engine: Coordination and high-level rules
%IR.Network{
  partition_id: "coordinator",
  remote_links: [
    %RemoteLink{
      link_id: "risk_engine",
      target_engine: %{type: :http_endpoint, url: "http://risk-service/api/rules"},
      consistency_level: :strong
    },
    %RemoteLink{
      link_id: "pricing_engine", 
      target_engine: %{type: :message_queue, queue: "pricing.requests"},
      consistency_level: :eventual
    }
  ]
}
```

### Pattern 3: Geographic Distribution
Distribute processing based on geographic regions or data locality.

```elixir
%IR.Network{
  partition_id: "us_west",
  remote_links: [
    %RemoteLink{
      link_id: "us_east_backup",
      target_engine: %{type: :distributed_node, node: :engine@us_east},
      sync_mode: :pull,  # Backup reads from primary
      fact_filters: [%FactFilter{sync_direction: :outbound}]
    }
  ]
}
```

## Extended Node Types

### Remote Proxy Node
Represents a node that executes on a remote engine.

```elixir
%IR.Node{
  type: :remote_proxy,
  link_id: String.t(),
  remote_node_id: String.t(),
  input_mapping: %{local_var => remote_var},
  output_mapping: %{remote_var => local_var},
  timeout_ms: pos_integer(),
  failure_mode: :fail | :skip | :retry
}
```

### Distributed Join Node
Joins facts across multiple engines.

```elixir
%IR.Node{
  type: :distributed_join,
  local_input: input_ref(),
  remote_inputs: [%{link_id: String.t(), node_id: String.t()}],
  join_conditions: [IR.JoinCond.t()],
  consistency_requirement: :eventual | :strong
}
```

### Fact Sync Node  
Explicitly synchronises facts with remote engines.

```elixir
%IR.Node{
  type: :fact_sync,
  direction: :send | :receive | :bidirectional,
  link_id: String.t(),
  fact_filter: IR.FactFilter.t(),
  sync_trigger: :immediate | :batched | :periodic
}
```

## Consistency Models

### Eventual Consistency
- Facts propagate asynchronously
- No ordering guarantees between engines
- Conflict resolution required
- Highest performance, lowest latency

### Causal Consistency  
- Preserves causality relationships
- Vector clocks track fact dependencies
- Moderate performance impact
- Suitable for most business rules

### Strong Consistency
- Synchronous fact propagation
- Global ordering of all changes
- Distributed consensus required
- Highest latency, strongest guarantees

## Communication Protocols

### Process-to-Process (Local)
```elixir
defmodule RulesEngine.Transport.Process do
  def send_facts(target_pid, facts, opts \\ [])
  def request_facts(target_pid, filter, opts \\ [])
  def execute_remote_node(target_pid, node_id, inputs, opts \\ [])
end
```

### Distributed Erlang
```elixir  
defmodule RulesEngine.Transport.DistributedNode do
  def connect_node(node_name, auth_cookie)
  def send_facts(target_node, target_process, facts, opts \\ [])
  def monitor_remote_engine(target_node, target_process)
end
```

### HTTP/REST API
```elixir
defmodule RulesEngine.Transport.HTTP do
  def post_facts(endpoint_url, facts, auth_headers \\ [])
  def get_facts(endpoint_url, filter, auth_headers \\ [])  
  def execute_node(endpoint_url, node_spec, inputs, auth_headers \\ [])
end
```

### Message Queue (AMQP/Kafka)
```elixir
defmodule RulesEngine.Transport.MessageQueue do
  def publish_facts(queue_name, facts, routing_key \\ "")
  def subscribe_facts(queue_name, fact_filter, callback)
  def request_response(request_queue, response_queue, payload, timeout)
end
```

## Coordination Algorithms

### Centralized Coordination
- Single coordinator manages execution order
- All engines report to coordinator before executing
- Simple but single point of failure

### Decentralized Coordination
- Engines coordinate directly with peers
- Distributed consensus for ordering (Raft/PBFT)
- More complex but fault-tolerant

### Hybrid Coordination
- Regional coordinators for local ordering
- Cross-region eventual consistency
- Balance between performance and consistency

## Failure Handling

### Connection Failures
```elixir
@type failure_mode ::
  :fail_fast |           # Immediately fail the rule execution
  :graceful_degradation | # Continue without remote facts
  :retry_with_backoff |   # Retry with exponential backoff
  :circuit_breaker        # Stop attempting after threshold
```

### Partial Network Partitions
- Detect split-brain scenarios
- Maintain read-only operations during partitions
- Reconcile state when partition heals

### Remote Engine Failures
- Health monitoring and failure detection
- Automatic failover to backup engines
- Graceful degradation of rule functionality

## Implementation Architecture

### Link Manager
```elixir
defmodule RulesEngine.Distributed.LinkManager do
  @callback establish_link(RemoteLink.t()) :: {:ok, connection()} | {:error, term()}
  @callback close_link(link_id()) :: :ok
  @callback send_facts(link_id(), [fact()], opts()) :: :ok | {:error, term()}
  @callback receive_facts(link_id(), timeout()) :: {:ok, [fact()]} | {:error, term()}
end
```

### Fact Synchroniser
```elixir
defmodule RulesEngine.Distributed.FactSync do  
  def start_sync_process(network, remote_links)
  def sync_facts_batch(link_id, facts, sync_mode)
  def resolve_conflicts(local_facts, remote_facts, resolution_strategy)
  def get_vector_clock(network_id)
end
```

### Distributed Runtime
```elixir
defmodule RulesEngine.Distributed.Runtime do
  def execute_distributed_cycle(network, context)
  def execute_remote_node(link_id, node_id, inputs, timeout)
  def coordinate_multi_engine_execution(engines, coordination_mode)
end
```

## Performance Optimisation

### Fact Replication Strategies
- **Lazy Replication**: Replicate facts only when needed
- **Eager Replication**: Proactively replicate based on filters
- **Hybrid Replication**: Combine lazy and eager based on fact types

### Network Topology Optimisation
- Minimise cross-engine joins
- Colocate related rules and facts
- Use hierarchy to reduce coordination overhead

### Caching and Prefetching
- Cache frequently accessed remote facts locally
- Prefetch facts based on rule execution patterns
- Invalidate caches based on fact update notifications

## Configuration

### Network Configuration
```elixir
config :rules_engine, :distributed,
  cluster_name: "production_rules",
  coordination_mode: :decentralized,
  default_consistency_level: :causal,
  fact_sync_batch_size: 1000,
  remote_call_timeout: 5000,
  connection_retry_attempts: 3
```

### Transport Configuration
```elixir
config :rules_engine, :transports,
  http: [
    timeout: 30_000,
    pool_size: 10,
    retry_attempts: 3
  ],
  message_queue: [
    broker_url: "amqp://localhost:5672",
    connection_pool_size: 5,
    prefetch_count: 100
  ]
```

## Migration Strategy

### Phase 1: Local Distribution
- Process-to-process communication
- Simple fact replication
- Basic failure handling

### Phase 2: Network Distribution  
- Distributed Erlang support
- Vector clocks for causality
- Advanced failure detection

### Phase 3: External Integration
- HTTP/REST APIs
- Message queue integration
- Multi-datacenter support

### Phase 4: Advanced Features
- Automatic network partitioning
- Dynamic load balancing
- Cross-region replication

## Monitoring and Observability

### Distributed Tracing
- Trace rule execution across engines
- Correlate facts and rule firings
- Measure cross-engine latencies

### Health Monitoring
```elixir
defmodule RulesEngine.Distributed.HealthCheck do
  def engine_health(engine_ref) :: :healthy | :degraded | :failed
  def link_status(link_id) :: :connected | :disconnected | :degraded
  def replication_lag(link_id) :: {:ok, milliseconds()} | {:error, term()}
end
```

### Performance Metrics
- Cross-engine fact synchronisation latency
- Remote node execution times
- Network partition and recovery times
- Conflict resolution frequency and impact
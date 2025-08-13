# Library API (Draft)

Public, library-native interfaces for compiling rules and running tenant engines.

## Modules and Types (conceptual)

- Network: immutable compiled RETE network (shared across engines)
- Engine.State: working memory, indexes, agenda, refraction table
- TenantKey :: term
- Fact :: map | struct with at least :id, :type, optional effective_from/to

## Compilation

- compile_dsl(source :: String.t(), opts :: keyword) :: {:ok, ir :: map} | {:error, issues}
- build_network(ir :: map, opts :: keyword) :: {:ok, network} | {:error, reason}

Options
- calculators: [module] — whitelist of calculator modules usable in guards/reducers
- strict?: boolean — fail on warnings

## Pure execution (no processes)

- new_state(network, opts) :: state
- step(state, {:assert | :modify | :retract, payload}, opts) :: {state, outputs}
  - assert payload: fact | [fact]
  - modify payload: fact | [fact]    # full replacement by id; partial patches are not supported in v0
  - retract payload: id | [id]
- run(state, [op], opts) :: {state, outputs}

Outputs (shape)
- %{
    activations: [activation],           # activation := %{production_id, token_signature, salience, inserted_at}
    derived: [fact],                     # derived facts with provenance embedded
    trace: [event]                       # optional, if tracing enabled
  }

## OTP runtime (per-tenant GenServer)

- start_tenant(tenant :: TenantKey, network | ir | source, opts) :: {:ok, pid} | {:error, reason}
- stop_tenant(tenant | pid) :: :ok
- whereis(tenant :: TenantKey) :: pid | nil

- assert(pid | tenant, facts :: fact | [fact], opts) :: :ok | {:ok, outputs}
- modify(pid | tenant, facts :: fact | [fact], opts) :: :ok | {:ok, outputs}
- retract(pid | tenant, ids :: id | [id], opts) :: :ok | {:ok, outputs}
- transact(pid | tenant, fun :: (-> any)) :: {:ok, outputs} | {:error, reason}
  - Executes fun, capturing assert/modify/retract calls, and applies them atomically as a batch; agenda fires after the batch up to fire_limit.
- load_rules(pid | tenant, network | ir | source, opts) :: :ok | {:error, reason}
  - Pauses agenda, swaps compiled network at a safe boundary, reconciles alpha memories, then resumes. No backfills in v0; previously derived facts remain until retracted by inputs.

Options
- return: :none | :activations | :derived | :all
- trace_id: term
- batch: boolean (process ops atomically)
- partition_key: term (advisory; engine may compute internally)
- fire_limit: non_neg_integer | :infinity

## Tracing and Introspection

- trace(pid | tenant, level | filter) :: :ok
- stats(pid | tenant) :: map
- dump_agenda(pid | tenant) :: [activation]
- list_tenants() :: [TenantKey]

## Calculators and Reducers

- behaviour Calculator: pure functions used by guards and helpers
- behaviour Reducer: accumulate reducers (sum, count, min, max, avg, custom)
- register_calculator(module) :: :ok
- register_reducer(module) :: :ok

## Errors (see specs/error_handling.md)

- {:error, :invalid_rule | :invalid_fact | :refraction_violation | :memory_budget | term}

## Notes

- The library does not prescribe storage, clustering, or external APIs.
- For concurrency, prefer the OTP runtime; pure execution APIs are ideal for tests and offline computations.

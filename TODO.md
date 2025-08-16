# TODO

A curated, actionable backlog to take RulesEngine from prototype to robust, documented library. Prioritised by impact and dependency.

## 0. Immediate hygiene

- [x] Replace README placeholder with real overview, usage, and examples (install, quickstart, compile DSL to IR, link to specs)
- [x] Pin supported Elixir version (1.18 stable) and CI matrix; resolved Dialyzer issues
- [x] Ensure all public modules have @moduledoc and functions have @doc/@specs
- [x] Add license file and project metadata (description, source_url, docs) in mix.exs
- [x] Enable strict compiler flags in mix.exs (warnings_as_errors in CI env) and ensure zero warnings

## 1. DSL parsing and validation

- [x] Extend grammar to cover:
  - [x] Negation/exists in when: not/exists forms (grammar + AST tags)
  - [x] Accumulate/group-by syntax as per specs/accumulation.md
  - [x] More boolean/collection ops (overlap, starts_with, contains) if part of DSL and Predicates
- [x] Implement parser recovery and human-readable errors (file:line, caret context)
- [x] Normalise AST format (consistent then/when tuple handling) and add type for AST nodes
- [x] Validation improvements:
  - [x] Cross-check bindings across all guard contexts (including nested and/or)
  - [x] Validate accumulate reducers and having clauses (types, names)
  - [x] Enforce allowed fields using fact schema registry; surface context-rich paths
  - [x] Predicate type expectation enforcement aligned with RulesEngine.Predicates.expectations/1

## 2. IR compilation

- [x] Build real Alpha network from fact patterns with index hints (op selectivity)
- [x] Build Beta network joins from guards and inter-binding comparisons
- [x] Encode not/exists nodes into network with correct semantics
- [x] Add action compilation to IR (emit, call, log actions with full schema compliance)
- [x] Implement accumulate nodes:
  - [x] Sum, count, min, max, avg reducers with proper IR encoding
  - [x] Group-by key encoding and incremental update policy
  - [x] Reducer bindings available in action clauses
  - [x] Having filters at compile-time into network nodes (parsed and stored in IR)
- [x] Add agenda policy data in IR (salience, recency, tiebreakers) from specs/agenda.md
- [x] Include refraction settings per rule (from specs/refraction.md)
- [x] Attach source map info (byte offsets) to IR nodes for traceability
- [x] Schema conformance hardening: round-trip cast where feasible before validate()

## 3. Engine runtime (OTP)

- [x] Define engine GenServer with:
  - [x] APIs: start/stop tenant, assert/modify/retract facts, run/step, reset, snapshot
  - [x] Working memory structures: alpha memories, beta memories, token tables, agenda queue
  - [x] Deterministic batch processing boundaries
- [x] Implement agenda policy module behaviour; default policy with salience + recency
- [x] Refraction store to avoid duplicate fires across stable inputs
- [x] Action RHS execution:
  - [x] Emit derived facts back into WM with lineage
  - [x] Optional callback hooks
- [x] Tracing bus:
  - [x] Node-level events (assert/retract, join, activation, fire)
  - [x] Token lineage, activation lifecycle events
  - [x] Pluggable subscribers

## 4. Fact schemas

- [x] Schema registry module with external configuration support
- [x] Remove built-in domain-specific schemas from library
- [x] Integrate external schemas into validation (types and allowed fields)
- [x] LLM integration support via `list_schemas/0` and `schema_details/0`

## 5. Standard library of predicates and calculators

- [x] Implement calculator functions referenced in DSL:
  - [x] time_between/3, bucket/2-3, decimal_* and dec/1
  - [x] Domain calculators as per specs/calculators.md
- [x] Expand RulesEngine.Predicates to support all documented ops; add docs and tests
- [x] Add pure, well-tested helpers to avoid runtime surprises; document expectations

## 6. Configuration & Extensibility

- [x] **BLOCKS PRODUCTION**: Configurable agenda policies - allow host applications to define rule ordering strategies
- [x] **BLOCKS PRODUCTION**: Configurable refraction policies - allow host applications to control rule re-firing behavior  
- [x] **BLOCKS PRODUCTION**: Pluggable predicate registry - enable host applications to add domain-specific predicates
- [x] **BLOCKS PRODUCTION**: Pluggable calculator functions - enable host applications to add domain-specific calculations
- [x] **BLOCKS PRODUCTION**: Configurable memory limits per tenant - prevent resource exhaustion
- [x] **BLOCKS PRODUCTION**: Configurable telemetry backends - allow host applications to choose monitoring systems
- [x] Configurable compilation cache settings - TTL, size limits, eviction policies
- [x] Configurable error formatting - allow host applications to customize error presentation
- [x] Plugin system for custom DSL extensions - enable domain-specific syntax
- [ ] Configurable network building strategies - balance compilation speed vs runtime performance

## 7. Performance optimization

- [x] **Foundation Infrastructure**:
  - [x] Add comprehensive benchmarking suite with Benchee
  - [x] Integrate :telemetry events for compilation and runtime profiling
  - [x] Add performance regression CI checks
  - [x] Memory profiling with :recon integration
- [x] **Compilation Optimization** (Critical - 7x performance gap):
  - [x] Implement compilation result caching (ETS-based, source checksum keys)
  - [x] Cache JSON schema validation (remove disk I/O from hot path)  
  - [x] **BLOCKS PRODUCTION**: Optimize O(n²) network building algorithms to O(n log n) - critical for >100 rule rulesets
  - [ ] Add parallel rule processing with Task.async_stream for multi-core compilation
- [ ] **Runtime Performance** (3x improvement target):
  - [ ] **BLOCKS PRODUCTION**: Replace O(n) priority queue with binary heap (gb_trees/custom heap) - essential for high-throughput scenarios
  - [ ] **BLOCKS PRODUCTION**: Implement ETS-based working memory for large fact sets (>100K facts) - required for multi-tenant scalability
  - [ ] Add memory pressure monitoring and fact eviction strategies - prevents OOM in production
  - [ ] Optimize validation with single-pass binding collection
- [ ] **Scalability Infrastructure** (Multi-tenant support):
  - [ ] **BLOCKS PRODUCTION**: Implement working memory partitioning (use existing partition_count field) - required for tenant isolation
  - [ ] Add incremental parsing for delta rule updates - enables zero-downtime deployments
  - [ ] **BLOCKS PRODUCTION**: Enable hot-swap capabilities for <50ms rule activation - critical for SaaS environments
  - [ ] Add resource isolation and tenant-specific memory budgets - prevents tenant interference
- [ ] **Memory Management**:
  - [ ] Convert Map/MapSet structures to ETS tables for large datasets
  - [ ] Implement fact deduplication and content-addressable storage
  - [ ] Add configurable cache limits and eviction policies

## 8. Tests and coverage

- [ ] **BLOCKS PRODUCTION**: End-to-end tests for all fixtures (currently parse + IR schema only) - ensures runtime correctness
- [ ] **BLOCKS PRODUCTION**: Property-based tests for parser with StreamData (round-trip idempotence, fuzz inputs) - critical for parser robustness
- [ ] Validation tests for error surfaces (unknown bindings, invalid operands, unknown fields)
- [ ] IR tests for guard flattening, set ops, between
- [ ] **BLOCKS PRODUCTION**: Engine integration tests: assert/modify/retract flows; refraction; agenda determinism - essential for runtime reliability
- [x] Coverage: ensure ExCoveralls gates in CI with threshold (e.g., 85%)
- [ ] **BLOCKS PRODUCTION**: Load testing framework - simulate production workloads (1000s tenants, millions of facts)
- [ ] **BLOCKS PRODUCTION**: Stress testing - validate engine behaviour under resource pressure
- [ ] **BLOCKS PRODUCTION**: Security testing - injection attacks, DoS resistance, tenant isolation breaches
- [ ] Mutation testing with Muzak - ensure test quality catches real bugs
- [ ] Contract testing - validate DSL backwards compatibility
- [ ] Performance regression testing - catch performance degradations in CI

## 9. Tooling and CI

- [x] Update .github/workflows/ci.yml to run:
  - [x] mix deps.get
  - [x] mix format --check-formatted
  - [x] mix compile --warnings-as-errors
  - [x] mix credo --strict
  - [x] mix dialyzer (cache plt)
  - [x] mix test and MIX_ENV=test mix test --cover
- [ ] Add dialyzer configuration for types in DSL modules
- [ ] Add pre-commit hooks suggestion (format, credo)

## 10. Documentation

- [ ] Write real README with:
  - [ ] Project overview, DSL snippet, compile example, IR snippet
  - [ ] Links to SPECS.md index
  - [ ] Stability and scope notes
- [ ] **BLOCKS PRODUCTION**: Module docs and function docs with doctests where useful - required for developer adoption
- [ ] Expand specs/* where noted "Next Steps":
  - [ ] Finalise minimal DSL primitives and examples
  - [ ] Agenda & refraction policy defaults, with examples
  - [ ] Temporal semantics: clear examples with edge cases (inclusive/exclusive bounds)
  - [ ] Performance targets and test methodology
- [ ] Add docs site config with ExDoc (groups for DSL, Compiler, Engine, Predicates)
- [ ] **BLOCKS PRODUCTION**: API reference documentation with comprehensive examples - essential for library adoption
- [ ] **BLOCKS PRODUCTION**: Architecture Decision Records (ADRs) - document design rationale for maintainability
- [ ] **BLOCKS PRODUCTION**: Migration guides - help users upgrade between versions
- [ ] **BLOCKS PRODUCTION**: Troubleshooting guide - reduce support burden
- [ ] **BLOCKS PRODUCTION**: Performance tuning guide - help users achieve production targets

## 11. JSON fixtures alignment

- [ ] Ensure all DSL fixtures have expected JSON comparison files or clarify partial coverage
- [ ] Add fixtures for accumulate, exists/not, complex guards
- [ ] Add golden IR fixtures to detect regressions in compiler

## 12. Error handling and messages

- [ ] **BLOCKS PRODUCTION**: Replace generic parser errors with user-friendly diagnostics - essential for developer experience
- [ ] **BLOCKS PRODUCTION**: Standardise error shape across parser/validator/compiler - required for consistent error handling
- [ ] Add actionable messages, include source spans and suggestions
- [ ] **BLOCKS PRODUCTION**: Custom exception types (RulesEngine.ParseError, CompileError, RuntimeError) - enables structured error handling
- [ ] **BLOCKS PRODUCTION**: Error recovery strategies - graceful handling of malformed rules without crashing engine
- [ ] **BLOCKS PRODUCTION**: Circuit breakers for tenant engines - prevent cascade failures from misbehaving tenants
- [ ] **BLOCKS PRODUCTION**: Replace try/catch blocks with idiomatic Elixir error handling patterns - follow "let it crash" philosophy
- [ ] Remove defensive try/rescue from registry modules (calculator, predicate, agenda, refraction) - let processes crash and restart cleanly
- [ ] Use pattern matching on function returns instead of catching all errors - make errors visible and debuggable
- [ ] Only catch specific expected errors in action_executor.ex for external callbacks - avoid hiding programming errors
- [ ] Dead letter queue for failed fact assertions - enable debugging of data quality issues
- [ ] Error rate monitoring and alerting - detect production issues early
- [ ] Structured logging with correlation IDs - enable distributed tracing of errors

## 13. Production Infrastructure

- [ ] **BLOCKS PRODUCTION**: Graceful shutdown handling - prevent data loss when host application shuts down
- [ ] Working memory serialization/deserialization - enable persistence by host applications
- [ ] **BLOCKS PRODUCTION**: Rate limiting per tenant - prevent resource exhaustion from misbehaving tenants
- [ ] **BLOCKS PRODUCTION**: Audit logging for rule changes and fact modifications - compliance requirement
- [ ] **BLOCKS PRODUCTION**: Configuration management - environment-specific settings without code changes
- [ ] Security hardening - input sanitisation, secure defaults, principle of least privilege
- [ ] Resource quotas and limits per tenant - prevent memory exhaustion
- [ ] **BLOCKS PRODUCTION**: Implement proper supervisor trees for crash recovery instead of try/catch - follow Erlang/OTP patterns
- [ ] Isolate risky operations (external callbacks, dynamic function calls) in separate supervised processes - enable fault tolerance
- [ ] Use process isolation for tenant engines - prevent cascade failures through proper supervision
- [ ] Database migrations for persistent working memory (future)

## 14. Packaging and releases

- [ ] **BLOCKS PRODUCTION**: Prepare Hex package metadata (links, maintainers, files) - required for public release
- [ ] **BLOCKS PRODUCTION**: Generate CHANGELOG and versioning policy - essential for upgrade planning
- [ ] Scripted release process; tag and docs publish
- [ ] Semantic versioning automation with conventional commits
- [ ] Security vulnerability scanning in CI
- [ ] License compliance checking

## 15. Developer experience

- [ ] **BLOCKS PRODUCTION**: Mix tasks - essential developer tools:
  - [ ] mix rules_engine.parse FILE
  - [ ] mix rules_engine.compile FILE --tenant TENANT --out ir.json
  - [ ] mix rules_engine.check FILE (parse + validate + schema)
  - [ ] mix rules_engine.benchmark - performance testing
- [ ] **BLOCKS PRODUCTION**: Error codes reference doc - enables proper error handling
- [ ] Quickstart guide mirroring AGENTS.md flow
- [ ] **BLOCKS PRODUCTION**: REPL helpers for debugging rules - improves development experience
- [ ] **BLOCKS PRODUCTION**: Rule testing framework - enables test-driven rule development
- [ ] Visual rule network debugger - helps debug complex rule interactions
- [ ] IDE plugins/extensions for syntax highlighting
- [ ] Hot reloading during development

## 16. Advanced Features (Future)

- [ ] Truth maintenance system (TMS) - enables belief revision and non-monotonic reasoning
- [ ] Backward chaining support - enables goal-directed reasoning
- [ ] Fuzzy logic operations - enables approximate reasoning with uncertainty
- [ ] Machine learning integration - enables data-driven rule discovery
- [ ] Rule versioning and rollback - enables safe production rule updates
- [ ] A/B testing framework for rules - enables experimentation
- [ ] Temporal reasoning with time windows - enables complex event processing
- [ ] Rule explanation system - enables transparency and debugging

## 17. Monitoring & Observability

- [ ] **BLOCKS PRODUCTION**: Enhanced telemetry integration - comprehensive metrics for production monitoring
- [ ] **BLOCKS PRODUCTION**: Distributed tracing support - enables debugging across microservices
- [ ] Custom metrics for business rules - enables domain-specific monitoring by host applications
- [ ] Telemetry event specification - enables host applications to implement alerting
- [ ] Structured event logging - enables host applications to implement log aggregation
- [ ] Memory usage tracking per tenant - enables resource management
- [ ] Rule execution latency histograms - enables performance tuning

## 18. Examples & Documentation

- [ ] **BLOCKS PRODUCTION**: Example applications - demonstrates real-world usage patterns:
  - [ ] Business rules example (generic entity processing)
  - [ ] Validation rules example (constraint checking)
  - [ ] Decision logic example (multi-factor calculations)
- [ ] Migration examples from other rule engines - reduces switching costs
- [ ] Performance tuning cookbook - helps achieve production targets

## 19. Nice-to-haves (later)

- [ ] Optional persistence adapters for working memory (behaviour + in-memory impl)
- [ ] Partial rete network visualiser from IR (graphviz)
- [ ] Interactive tracing viewer (text-first)

---

Legend:

- [ ] Not started
- [ ] In progress
- [x] Done

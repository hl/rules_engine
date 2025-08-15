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

## 6. Performance optimization

- [ ] **Foundation Infrastructure**:
  - [ ] Add comprehensive benchmarking suite with Benchee
  - [ ] Integrate :telemetry events for compilation and runtime profiling
  - [ ] Add performance regression CI checks
  - [ ] Memory profiling with :recon integration
- [ ] **Compilation Optimization** (Critical - 7x performance gap):
  - [ ] Implement compilation result caching (ETS-based, source checksum keys)
  - [ ] Cache JSON schema validation (remove disk I/O from hot path)  
  - [ ] Optimize O(n²) network building algorithms to O(n log n)
  - [ ] Add parallel rule processing with Task.async_stream
- [ ] **Runtime Performance** (3x improvement target):
  - [ ] Replace O(n) priority queue with binary heap (gb_trees/custom heap)
  - [ ] Implement ETS-based working memory for large fact sets
  - [ ] Add memory pressure monitoring and fact eviction strategies
  - [ ] Optimize validation with single-pass binding collection
- [ ] **Scalability Infrastructure** (Multi-tenant support):
  - [ ] Implement working memory partitioning (use existing partition_count field)
  - [ ] Add incremental parsing for delta rule updates  
  - [ ] Enable hot-swap capabilities for <50ms rule activation
  - [ ] Add resource isolation and tenant-specific memory budgets
- [ ] **Memory Management**:
  - [ ] Convert Map/MapSet structures to ETS tables for large datasets
  - [ ] Implement fact deduplication and content-addressable storage
  - [ ] Add configurable cache limits and eviction policies

## 7. Tests and coverage

- [ ] End-to-end tests for all fixtures (currently parse + IR schema only)
- [ ] Property-based tests for parser (round-trip idempotence, fuzz inputs)
- [ ] Validation tests for error surfaces (unknown bindings, invalid operands, unknown fields)
- [ ] IR tests for guard flattening, set ops, between
- [ ] Engine integration tests (when runtime exists): assert/modify/retract flows; refraction; agenda determinism
- [x] Coverage: ensure ExCoveralls gates in CI with threshold (e.g., 85%)

## 8. Tooling and CI

- [x] Update .github/workflows/ci.yml to run:
  - [x] mix deps.get
  - [x] mix format --check-formatted
  - [x] mix compile --warnings-as-errors
  - [x] mix credo --strict
  - [x] mix dialyzer (cache plt)
  - [x] mix test and MIX_ENV=test mix test --cover
- [ ] Add dialyzer configuration for types in DSL modules
- [ ] Add pre-commit hooks suggestion (format, credo)

## 9. Documentation

- [ ] Write real README with:
  - [ ] Project overview, DSL snippet, compile example, IR snippet
  - [ ] Links to SPECS.md index
  - [ ] Stability and scope notes
- [ ] Module docs and function docs with doctests where useful
- [ ] Expand specs/* where noted “Next Steps”:
  - [ ] Finalise minimal DSL primitives and examples
  - [ ] Agenda & refraction policy defaults, with examples
  - [ ] Temporal semantics: clear examples with edge cases (inclusive/exclusive bounds)
  - [ ] Performance targets and test methodology
- [ ] Add docs site config with ExDoc (groups for DSL, Compiler, Engine, Predicates)

## 10. JSON fixtures alignment

- [ ] Ensure all DSL fixtures have expected JSON comparison files or clarify partial coverage
- [ ] Add fixtures for accumulate, exists/not, complex guards
- [ ] Add golden IR fixtures to detect regressions in compiler

## 11. Error handling and messages

- [ ] Replace generic parser errors with user-friendly diagnostics
- [ ] Standardise error shape across parser/validator/compiler
- [ ] Add actionable messages, include source spans and suggestions

## 12. Packaging and releases

- [ ] Prepare Hex package metadata (links, maintainers, files)
- [ ] Generate CHANGELOG and versioning policy
- [ ] Scripted release process; tag and docs publish

## 13. Developer experience

- [ ] Mix tasks:
  - [ ] mix rules_engine.parse FILE
  - [ ] mix rules_engine.compile FILE --tenant TENANT --out ir.json
  - [ ] mix rules_engine.check FILE (parse + validate + schema)
- [ ] Error codes reference doc
- [ ] Quickstart guide mirroring AGENTS.md flow

## 14. Nice-to-haves (later)

- [ ] Optional persistence adapters for working memory (behaviour + in-memory impl)
- [ ] Partial rete network visualiser from IR (graphviz)
- [ ] Interactive tracing viewer (text-first)

---

Legend:

- [ ] Not started
- [ ] In progress
- [x] Done

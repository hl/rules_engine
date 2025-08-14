# TODO

A curated, actionable backlog to take RulesEngine from prototype to robust, documented library. Prioritised by impact and dependency.

## 0. Immediate hygiene

- [x] Replace README placeholder with real overview, usage, and examples (install, quickstart, compile DSL to IR, link to specs)
- [x] Pin supported Elixir version (1.19 stable) and CI matrix; remove rc tag in mix.exs once stable
- [x] Ensure all public modules have @moduledoc and functions have @doc/@specs
- [x] Add license file and project metadata (description, source_url, docs) in mix.exs
- [x] Enable strict compiler flags in mix.exs (warnings_as_errors in CI env) and ensure zero warnings

## 1. DSL parsing and validation

- [ ] Extend grammar to cover:
  - [x] Negation/exists in when: not/exists forms (grammar + AST tags)
  - [ ] Accumulate/group-by syntax as per specs/accumulation.md
  - [ ] More boolean/collection ops (overlap, starts_with, contains) if part of DSL and Predicates
- [ ] Implement parser recovery and human-readable errors (file:line, caret context)
- [ ] Normalise AST format (consistent then/when tuple handling) and add type for AST nodes
- [ ] Validation improvements:
  - [ ] Cross-check bindings across all guard contexts (including nested and/or)
  - [ ] Validate accumulate reducers and having clauses (types, names)
  - [ ] Enforce allowed fields using fact schema registry; surface context-rich paths
  - [ ] Predicate type expectation enforcement aligned with RulesEngine.Predicates.expectations/1

## 2. IR compilation

- [ ] Build real Alpha network from fact patterns with index hints (op selectivity)
- [ ] Build Beta network joins from guards and inter-binding comparisons
- [ ] Encode not/exists nodes into network with correct semantics
- [ ] Implement accumulate nodes:
  - [ ] Sum, count, min, max reducers
  - [ ] Group-by key encoding and incremental update policy
  - [ ] Having filters at compile-time into network nodes
- [ ] Add agenda policy data in IR (salience, recency, tiebreakers) from specs/agenda.md
- [ ] Include refraction settings per rule (from specs/refraction.md)
- [ ] Attach source map info (byte offsets) to IR nodes for traceability
- [ ] Schema conformance hardening: round-trip cast where feasible before validate()

## 3. Engine runtime (OTP)

- [ ] Define engine GenServer with:
  - [ ] APIs: start/stop tenant, assert/modify/retract facts, run/step, reset, snapshot
  - [ ] Working memory structures: alpha memories, beta memories, token tables, agenda queue
  - [ ] Deterministic batch processing boundaries
- [ ] Implement agenda policy module behaviour; default policy with salience + recency
- [ ] Refraction store to avoid duplicate fires across stable inputs
- [ ] Action RHS execution:
  - [ ] Emit derived facts back into WM with lineage
  - [ ] Optional callback hooks
- [ ] Tracing bus:
  - [ ] Node-level events (assert/retract, join, activation, fire)
  - [ ] Token lineage, activation lifecycle events
  - [ ] Pluggable subscribers

## 4. Fact schemas

- [ ] Provide canonical fact schemas per specs/fact_schemas.md (structs or maps with enforced IDs)
- [ ] Add schema registry module and loader (allow custom schemas per tenant)
- [ ] Integrate schemas into validation (types and allowed fields)

## 5. Standard library of predicates and calculators

- [ ] Implement calculator functions referenced in DSL:
  - [ ] time_between/3, bucket/2-3, decimal_* and dec/1
  - [ ] Domain calculators as per specs/calculators.md
- [ ] Expand RulesEngine.Predicates to support all documented ops; add docs and tests
- [ ] Add pure, well-tested helpers to avoid runtime surprises; document expectations

## 6. Tests and coverage

- [ ] End-to-end tests for all fixtures (currently parse + IR schema only)
- [ ] Property-based tests for parser (round-trip idempotence, fuzz inputs)
- [ ] Validation tests for error surfaces (unknown bindings, invalid operands, unknown fields)
- [ ] IR tests for guard flattening, set ops, between
- [ ] Engine integration tests (when runtime exists): assert/modify/retract flows; refraction; agenda determinism
- [ ] Coverage: ensure ExCoveralls gates in CI with threshold (e.g., 85%)

## 7. Tooling and CI

- [ ] Update .github/workflows/ci.yml to run:
  - [ ] mix deps.get
  - [ ] mix format --check-formatted
  - [ ] mix compile --warnings-as-errors
  - [ ] mix credo --strict
  - [ ] mix dialyzer (cache plt)
  - [ ] mix test and MIX_ENV=test mix test --cover
- [ ] Add dialyzer configuration for types in DSL modules
- [ ] Add pre-commit hooks suggestion (format, credo)

## 8. Documentation

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

## 9. JSON fixtures alignment

- [ ] Ensure all DSL fixtures have expected JSON comparison files or clarify partial coverage
- [ ] Add fixtures for accumulate, exists/not, complex guards
- [ ] Add golden IR fixtures to detect regressions in compiler

## 10. Error handling and messages

- [ ] Replace generic parser errors with user-friendly diagnostics
- [ ] Standardise error shape across parser/validator/compiler
- [ ] Add actionable messages, include source spans and suggestions

## 11. Performance and memory

- [ ] Benchmarks for parser, compiler, and (later) runtime networks
- [ ] Micro-bench for predicate evaluation and term encoding
- [ ] Memory profiling for large rule sets and fact volumes
- [ ] Index selection strategy based on Predicates.selectivity_hint/1

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

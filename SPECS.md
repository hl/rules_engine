# RulesEngine Specs — Overview and Index

This document is the entry point for the RulesEngine RETE engine specifications and an index of detailed specs in the `specs/` folder. It captures high-level goals, shared requirements, and the primary use cases driving the design.

## Goals

- Correctness: Deterministic, traceable rule evaluation over changing facts.
- Incrementality: Efficient processing of assert/modify/retract without full re-evaluation.
- Reuse: Shared Alpha/Beta nodes across rules to minimize duplicate work.
- Extensibility: Pluggable agenda policies, refraction controls, and DSL expansion.
- Observability: Tracing, introspection, and reproducible test scenarios.
- Scale: Sustain many concurrent tenant engines within a node; each with 100k–2M facts and ~50–500 rules.
- Multi-tenancy: Per-tenant engines managed by the library runtime; rules are precompiled to IR/network and activated deterministically.
- Library-first: No UI/gRPC; embed as an Elixir library with clear APIs.

## Scope

RulesEngine is a RETE-based rule engine library for Elixir.
Domain examples (payroll, compliance, wage cost estimation) are provided as reference patterns in the examples, not as product scope.
The engine supports single-fact filtering (Alpha network) and multi-fact joins/aggregations (Beta network), including negation and existence checks. For some calculations (e.g., overtime totals), accumulation over groups is required.

## Core Requirements

- Facts (WMEs): Maps or structs with stable IDs, type tags, and effective time ranges.
- Operations: `assert`, `modify`, `retract` with idempotent handling and proper token cleanup.
- Alpha Network: Attribute tests, indexing, and memories to rapidly filter candidate facts.
- Beta Network: Joins, negative/exists nodes, and accumulate/group-by for totals.
- Agenda: Salience/priority and recency strategies; deterministic ordering under a fixed policy.
- Refraction: Prevent repeat firing on identical token combinations until inputs change.
- Actions: RHS can emit derived facts (e.g., `PayLine`, `ComplianceViolation`, `CostEstimate`) and/or invoke callbacks.
- Tracing: Node-level events for asserts/retracts, token lineage, and activation lifecycle.

## Design Notes (Elixir)

- Engine as a `GenServer` (or supervised components) owning network and agenda.
- Batch processing of input deltas for consistency; explicit boundaries for actions.
- Rule DSL via macros; compile-time network build with node sharing and indexing.
- Pluggable storage for working memory (in-memory by default, hooks for persistence later).
- Runtime as OTP processes: per-tenant Engine GenServers own working memory, indexes, and agenda. Optional PartitionSupervisor for internal parallelism. No Phoenix/gRPC in scope.

## Specs Index

| Topic | Path | Summary |
| --- | --- | --- |
| RETE Overview | [specs/rete_overview.md](specs/rete_overview.md) | Concepts, Alpha/Beta networks, agenda, refraction |
| Library API | [specs/library_api.md](specs/library_api.md) | Public functions for compile/run/tracing |
| Architecture | [specs/architecture.md](specs/architecture.md) | Library runtime, per-tenant GenServers, network representation |
| Architecture (Library + OTP) | [specs/architecture.md](specs/architecture.md) | Engine runtime, per-tenant GenServers, optional partitioning |
| Calculators | [specs/calculators.md](specs/calculators.md) | Deterministic helpers for guards/reducers |
| DSL Examples | [specs/dsl_examples.md](specs/dsl_examples.md) | Domain examples (payroll, compliance, estimation) |
| Rule DSL | [specs/dsl.md](specs/dsl.md) | Textual DSL and compilation |
| DSL EBNF | [specs/dsl_ebnf.md](specs/dsl_ebnf.md) | Formal grammar |
| IR Schema | [specs/ir.schema.json](specs/ir.schema.json) | JSON schema for compiled IR |
| Compiler IR | [specs/compiler_ir.md](specs/compiler_ir.md) | Node graph and internal IR |
| Parser Contract | [specs/parser_contract.md](specs/parser_contract.md) | Parser-to-compiler contract |
| Fact Schemas | [specs/fact_schemas.md](specs/fact_schemas.md) | Canonical WME structures and IDs |
| Temporal Semantics | [specs/temporal_semantics.md](specs/temporal_semantics.md) | Effective time ranges and filtering |
| Accumulation | [specs/accumulation.md](specs/accumulation.md) | Group-by nodes and incremental aggregates |
| Agenda Policy | [specs/agenda.md](specs/agenda.md) | Conflict resolution, salience, recency |
| Refraction Policy | [specs/refraction.md](specs/refraction.md) | Duplicate-fire suppression semantics |
| Error Handling | [specs/error_handling.md](specs/error_handling.md) | Failures, retries, guardrails |
| Tracing & Introspection | [specs/tracing.md](specs/tracing.md) | Events, callbacks, introspection |
| Performance | [specs/performance.md](specs/performance.md) | Throughput, memory, latency targets and benchmarks |
| Domain Examples — Payroll | [specs/payroll.md](specs/payroll.md) | Example rules and facts |
| Domain Examples — Compliance | [specs/compliance.md](specs/compliance.md) | Example rules and facts |
| Domain Examples — Wage Cost Estimation | [specs/wage_cost_estimation.md](specs/wage_cost_estimation.md) | Example rules and facts |
These detailed specs enumerate facts, constraints, rule shapes, agenda needs, and outputs for each domain and cross-cutting concern.

## Next Steps

- Finalize minimal DSL primitives (patterns, guards, join conditions, not/exists, accumulate).
- Define canonical fact schemas shared across use cases (IDs, timestamps, keys).
- Establish agenda policy defaults and refraction semantics.
- Build Alpha network and a subset of Beta joins; iterate with the Payroll spec first.

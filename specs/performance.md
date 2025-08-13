# Performance Targets and Methodology

Includes concrete targets and a results table to update post-implementation.
Defines SLAs and how to measure them. Includes single-tenant and multi-tenant scale targets.

## Scale Targets (Concurrent)

- Tenants: many concurrent engine instances (tenant engines) within a node or across nodes (deployment out of scope).
- Working set per tenant: 100k–2M facts (WMEs).
- Rules: 50–500 rules per tenant compiled into a shared network.
- Throughput: Support continuous delta ingestion (assert/modify/retract) without tail-latency spikes.
- Tail latency: p95 propagation for small deltas (<= 100 facts) under 1s per tenant under mixed loads. Processing speed is the primary objective; prefer simpler designs that meet these targets (BSSN).
- Startup: First network build for 500 rules < 3s (warm cache target < 1s); bulk load of 2M facts < 2 min with indexed alpha inserts.
- Memory: Budget ~1.5–2.5 GB per active 2M-fact tenant in in-memory/ETS mode; total capacity sized across nodes for 1000 tenants (many will be smaller than max).

## Targets (Single-Tenant Baseline)

- Payroll weekly recompute: 10k employees, < 1s for small deltas (<= 100 entries).
- Compliance checks: < 500ms to evaluate new timesheet entry and related credentials.
- Estimation scenario: 100k scheduled shifts; first build < 5s, small deltas < 1s.
- Memory: Fit within 1 GB for above scenarios using in-memory backend.

## Compilation Targets

- Validate+Compile 500-rule tenant ruleset: < 3s on a modern CPU, cold cache; < 1s warm cache.
- Activate ruleset (hot-swap): Agenda-safe atomic switch with no more than 50ms pause per engine.

## Datasets

- Synthetic generators for employees, timesheets, policies with realistic distributions.
- Replay traces for modify/retract churn.

## Methodology

- Warm-up run, then N measured runs; report p50/p95.
- Isolate GC effects; record BEAM schedulers and ETS sizes.
- Compare agenda policies and indexing strategies.
- Measure with 1000 concurrent engines (mixed sizes) using a tenant orchestrator; apply coordinated omission-safe timers.
- Include scenarios with a small fraction of large tenants (2M facts, 500 rules) and a majority of small/medium tenants.
- Include GC in measurements; report impact of telemetry handlers off vs sampled; keep vendor backends out of hot path.

## Optimization Levers

- Alpha key selection and predicate ordering.
- Hash join key choice; beta memory indexing.
- Accumulate node design and reducer choice.
  - Group index load factor and reducer state footprint.
  - Incremental update costs on assert/modify/retract; cap group cardinality where needed.

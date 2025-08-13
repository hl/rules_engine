# Tracing and Introspection

Provides visibility via :telemetry events; vendor-neutral, pluggable handlers provide export to Prometheus/OTel/StatsD.

## Events

- `:alpha_enter` / `:alpha_leave` — WME passes/fails alpha test.
- `:alpha_store` / `:alpha_remove` — WME enters/leaves alpha memory.
- `:beta_join` — left token joined with right input.
- `:token_add` / `:token_remove` — beta memory changes.
- `:acc_group_create` / `:acc_group_update` / `:acc_group_delete` — accumulate group lifecycle with reducer deltas.
- `:activation_add` / `:activation_remove` — agenda changes.
- `:rule_fire` — rule RHS executed.
- `:emit` — derived fact emitted.
Each event includes `engine_id`, `node_id`, `rule_id?`, `trace_id`, timestamps, and key payload.

## Subscriptions

- `subscribe(engine, filter)` streams events matching `filter` (by rule_id, node_id, event types).
- Sampling: Rate or probability-based sampling to reduce volume in prod.
- Defaults at Scale: With 1000 concurrent engines, default to tracing disabled; enable sampling (<= 0.1–1%) and per-tenant plus global node rate limits. Provide coarse counters when tracing is off.

## Introspection APIs

- `network(engine)` — static graph with nodes/edges and attributes.
- `stats(engine)` — per-node counts, memory sizes, agenda length.
- `dump_trace(engine, opts)` — export recent events for analysis.

## Metrics (via :telemetry)

- Throughput: deltas/sec, activations/sec, rules fired/sec.
- Latency: p50/p95 propagation and activation-to-fire latency.
- Memory: WME count, alpha/beta memory sizes.

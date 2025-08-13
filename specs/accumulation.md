# Accumulation Semantics

See also: specs/calculators.md for reducers and helper functions used by accumulate nodes and guards.

Defines group-by and reducer behavior for incremental aggregates.

## Grouping

- Group key: Deterministic tuple built from declared fields in order.
- Key stability: Changing a grouping field triggers retract-from-old-group and assert-into-new-group.

## Reducers

- sum(expr): Decimal-accurate summation; Kahan compensation optional (off by default) to reduce rounding error when summing many terms.
- count(): Integer count of items in group.
- min(expr), max(expr): Track extreme value and a representative item if needed.
- avg(expr): Represented as `{sum, count}`; consumers compute Decimal division.
- collect(expr, limit: n): Bounded list/multiset; maintains counts up to `n` items.
- custom(name, init, add, remove, merge): User-provided reducer callbacks for advanced needs.

## Incremental Updates

- assert: evaluate expressions, update reducer state, emit delta if threshold conditions change.
- modify: compute old vs new contributions; remove old, add new.
- retract: remove contribution; if group becomes empty, drop aggregate.

## Precision and Rounding

- Monetary results use `Decimal`; rounding policy configurable per rule (`:half_up` default) and per emission site.
- Hours precision defaults to 2 decimal places; configurable.

## Exposure

- Accumulate outputs flow as tokens with fields bound via `as` clause; can be joined further or used in guards.

## Scale Notes

- Large Groups: When group cardinality is high (e.g., millions), prefer grouping keys aligned with partitions to keep aggregates local.
- Memory Caps: Reducers like `collect/2` must enforce limits strictly; provide truncation indicators in outputs.
- Windowed Aggregates: Consider time-windowed accumulation for rolling metrics to bound state.

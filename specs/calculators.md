# Calculators

Predefined, pure functions available in DSL expressions for precise, fast, reusable computations.

## Goals

- Speed and safety (deterministic, side‑effect free)
- Centralise payroll/time maths with precise semantics
- Keep surface minimal (BSSN)

## Semantics

- Pure, total on valid inputs; return {:error, reason} in IR or raise descriptive compiler error on invalid usage
- Timezone‑aware where applicable
- Decimal arithmetic for monetary ops
- No I/O, randomness, or clock reads; deterministic only

## Initial Set (v0)

- time_between(start :: DateTime, finish :: DateTime, unit :: :minutes | :hours) :: Decimal
  - Uses timezone‑aware diff; returns Decimal with scale 2 for hours, 0 or 2 for minutes (configurable)
- overlap_hours(a_start, a_end, b_start, b_end) :: Decimal
  - Returns hours of overlap as Decimal(2)
- bucket(period :: :day | :week, t :: DateTime, tz? :: String.t() | nil) :: term
  - Day = {:day, tz, date}; Week = {:week, tz, year, iso_week}
- decimal_add(a :: Decimal, b :: Decimal) :: Decimal
- decimal_mul(a :: Decimal, b :: Decimal) :: Decimal

## DSL Exposure and Imports

- Available in guards and RHS expressions
- Must be explicitly imported via an `imports` block; only whitelisted functions are callable.
- Example (DSL):

```dsl
imports
  use TimeCalcs: time_between, overlap_hours, bucket
  use Money: decimal_add, decimal_mul

rule "base-pay" do
  when
    ts: TimesheetEntry(start_at: s, end_at: f)
    guard time_between(s, f, :hours) > dec("0")
  then
    emit PayLine(hours: time_between(s, f, :hours), amount: decimal_mul(rate, time_between(s, f, :hours)))
end
```

## IR Mapping

- Map to Expr ops: {:time_between, [s, f, unit]}, {:overlap_hours, [...]}, {:bucket, [...]}, {:d_add, [a,b]}, {:d_mul, [a,b]}
- Compiler may specialise/in-line hot ops at nodes

## Precision

- Decimal scale for hours defaults to 2; configurable per rule
- Monetary operations always Decimal; accumulators may enable Kahan compensation globally

## Errors

- time_between: raise on finish < start? decide policy → allow negative durations or normalise; default: allow negative (caller can guard)
- bucket: requires timezone when jurisdiction rules differ; if omitted, uses t.zone

## Out of Scope (now)

- Complex calendars/holiday logic (handled by rules)
- Currency conversion
- Vectorised ops

# Wage Cost Estimation — Use-Case Specification

## Objective

Estimate wage costs (base, overtime, benefits, employer taxes) for planned or actual schedules. Produce `CostEstimate` facts by employee/team/project and time bucket. Use calculators for precise time and Decimal money maths (see calculators.md).

## Inputs (Facts)

- `ScheduledShift` (id, employee_id or role, start_at, end_at, planned_hours, location, project_id, scenario_id)
- `RateCard` (id, role or employee_id, base_rate, premiums, effective_from/to)
- `OvertimePolicy` (as in Payroll; may be role/location specific)
- `HolidayCalendar` (location, date, premium_multiplier)
- `ProjectAssignment` (employee_id, project_id, effective_from/to, cost_center)
- `Scenario` (id, name, parameters; optional toggles for rules)

## Outputs (Derived Facts)

- `CostEstimate` (scope: :employee|:team|:project, scope_id, bucket: :day|:week, hours, base_amount, overtime_amount, premium_amount, total_amount, scenario_id)
- `EstimateSummary` (scenario_id, totals by bucket and scope)

## Alpha Network (Single-Fact Filters)

- Filter `ScheduledShift` by `scenario_id`, date range, location.
- Filter `RateCard`, `OvertimePolicy`, `HolidayCalendar` by effective windows and scope.
- Filter `ProjectAssignment` by effective windows.

## Beta Network (Joins and Accumulations)

- Join `ScheduledShift` → `RateCard` via role/employee and effective period.
- Compute shift hours: `time_between/3` minus `break_minutes`/60 where available.
- Join with `OvertimePolicy` to compute base vs overtime components per bucket using `bucket/2-3` and Decimal ops.
- Join with `HolidayCalendar` and apply premium multipliers for overlapping dates; compute overlap with `overlap_hours/4`.
- Join with `ProjectAssignment` to attribute cost to project/cost centers.
- Accumulate by (scope, scope_id, bucket) to produce `CostEstimate` facts; sum with Decimal ops; apply percentage adds for employer taxes/benefits as separate components when needed.

## Example DSL Snippet

```dsl
imports
  use TimeCalcs: time_between, bucket
  use Money: decimal_add, decimal_mul

rule "shift_hours" salience: 300 do
  when
    shift: ScheduledShift(employee_id: e, start_at: s, end_at: f, break_minutes: bm)
    guard time_between(s, f, :hours) > dec("0")
  then
    emit ShiftCost(employee_id: e,
      bucket: bucket(:week, s),
      hours: decimal_add(time_between(s, f, :hours), dec("0"))  # minus breaks if available)
end

rule "base_cost" salience: 250 do
  when
    sc: ShiftCost(employee_id: e, bucket: b, hours: h)
    rc: RateCard(employee_id: e, base_rate: r, effective_from: ef, effective_to: et)
    guard b between ef and et
  then
    emit ShiftCost(employee_id: e, bucket: b, base_amount: decimal_mul(r, h))
end

rule "taxes_and_benefits" salience: 150 do
  when
    prof: EmployeeProfile(employee_id: e, health_insurance_cost_per_period: hi, fica_tax_rate: fica, unemployment_tax_rate: u)
    agg: accumulate from ShiftCost(employee_id: e, bucket: b, base_amount: ba)
         group_by e, b
         reduce gross: sum(ba)
  then
    emit CostEstimate(scope: :employee, scope_id: e, bucket: b,
      base_amount: gross,
      benefits_amount: hi,
      tax_amount: decimal_add(decimal_mul(gross, fica), decimal_mul(gross, u)),
      total_amount: decimal_add(decimal_add(gross, hi), decimal_add(decimal_mul(gross, fica), decimal_mul(gross, u))))
end
```

## Agenda and Ordering

- Salience ordering:
  - 100: Bucketization and hour accumulation
  - 90: Apply overtime split per bucket
  - 80: Apply holiday/premium adjustments
  - 30: Emit `CostEstimate`, then `EstimateSummary`
- Determinism: stable ordering by (scenario_id, scope, scope_id, bucket).

## Refraction

Avoid duplicate estimates for the same (scenario_id, scope, scope_id, bucket); retract on schedule/rate/policy changes.

## Edge Cases

- Shifts crossing buckets (midnight/week boundary) → split hours and costs.
- Role-based vs employee-specific rate precedence; mid-bucket rate changes.
- Scenario toggles enabling/disabling specific premiums/policies.

## Performance Targets (Initial)

- Handle 100k planned shifts per scenario; incremental recompute for small changes within a second.
- Alpha indexing by `scenario_id`, `role/employee_id`, and dates.

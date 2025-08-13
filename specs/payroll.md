# Payroll — Use-Case Specification

## Objective

Compute employee pay from timesheets, policies, and rates, including base pay, overtime, and premiums; emit `PayLine` facts suitable for downstream payroll processing. Main focus is processing speed; use calculators for precise time and money maths (see calculators.md).

## Inputs (Facts)

- `Employee` (id, role, location, union, employment_type, effective_from/to)
- `TimesheetEntry` (id, employee_id, start_at, end_at, hours, project_id, cost_center, approved?)
- `PayRate` (id, employee_id or role, rate_type: :hourly|:salary, base_rate, effective_from/to)
- `OvertimePolicy` (id, jurisdiction or union, threshold_hours, multiplier, period: :daily|:weekly)
- `Holiday` (id, date, location, premium_multiplier)
- `ShiftDifferential` (id, window, multiplier or fixed, location/role filters)
- `Deduction`/`EarningRule` (optional adjustments, effective periods)

## Outputs (Derived Facts)

- `PayLine` (employee_id, period_key, component: :base|:overtime|:premium, hours, rate, amount, provenance)
- `PayrollSummary` (employee_id, period_key, gross_amount, breakdown)

## Alpha Network (Single-Fact Filters)

- Filter `TimesheetEntry` by `approved? == true`, date range, `employee_id`.
- Compute payable hours per shift using `time_between(start_at, end_at, :hours)` minus `break_minutes`/60 as applicable; store as a field for downstream joins/accumulations.
- Filter `PayRate` and `OvertimePolicy` by effective period, jurisdiction, role/union.
- Filter `Holiday` and `ShiftDifferential` by location/date/time window.

## Beta Network (Joins and Accumulations)

- Join `TimesheetEntry -> Employee` on `employee_id` to attach role/location.
- Join with applicable `PayRate` using role/employee match and effective window.
- Join with `OvertimePolicy` via jurisdiction/union and effective period.
- Premiums: Join with `Holiday`/`ShiftDifferential` where entry overlaps date/time window; use `overlap_hours/4` to compute premium hours precisely. Prefer UTC-normalised instants; bucket periods via `bucket/2`.
- Accumulate base hours by (employee_id, `bucket(:week, start_at)` or policy period) using `accumulate ... reduce hours: sum(time_between/3)`; compare to policy thresholds.
  - If accumulated base hours > threshold, split into base and overtime components (excess goes to overtime).

## Agenda and Ordering

- Salience ordering:
  - 100: Base `PayLine` creation
  - 90: Overtime split and `PayLine` adjustments
  - 80: Premium additions (holiday/shift)
  - 20: `PayrollSummary` aggregation
- Determinism: stable ordering by (employee_id, period_key) when emitting lines.

## Refraction

Avoid duplicate `PayLine` emission for the same (employee_id, period_key, component, provenance). Retract/modify should remove/update previously emitted lines.

## Edge Cases

- Overlapping entries and DST changes; compute hours using timezone-aware arithmetic.
- Mid-period rate changes → prorate lines across effective windows.
- Retro adjustments (modify/retract) must propagate to summaries.
- Salary employees: either ignore timesheets or convert to standard hours as configured.

## Performance Targets (Initial)

- 10k employees, 1 week of entries: incremental update < 1s for small deltas.
- Memory bounded by active period; use alpha indexing on `employee_id` and dates.

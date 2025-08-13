# Compliance — Use-Case Specification

## Objective

Evaluate policy and regulatory constraints over work activity and credentials; emit `ComplianceStatus` and `ComplianceViolation` facts per employee and period.
Use calculators for precise hour math and threshold validation (see calculators.md).

## Inputs (Facts)

- `Employee` (id, role, location, union, manager_id)
- `TimesheetEntry` (id, employee_id, start_at, end_at, hours, location)
- `BreakRecord` (id, timesheet_entry_id, start_at, end_at, type)
- `TrainingRecord` (id, employee_id, training_type, completed_at, expires_at)
- `Certification` (id, employee_id, cert_type, issued_at, expires_at)
- `PolicyRule` (id, rule_type, params, effective_from/to, jurisdiction/role filters)
- `LocationRegulation` (id, location, constraint_type, params)

## Outputs (Derived Facts)

- `ComplianceStatus` (employee_id, period_key, status: :ok|:violations, counts)
- `ComplianceViolation` (employee_id, period_key, code, severity, details, provenance)

## Alpha Network (Single-Fact Filters)

- Filter `TrainingRecord`/`Certification` by validity windows.
- Filter `TimesheetEntry` by location/role period windows.
- Select `PolicyRule`/`LocationRegulation` applicable to role/jurisdiction and period.

## Beta Network (Joins, Negation, Accumulation)

- Missing training/certification: `Employee` not joined with required `TrainingRecord`/`Certification` (negation).
- Rest/break rules: Join `TimesheetEntry` with `BreakRecord`; accumulate total break minutes using `accumulate ... reduce minutes: sum(time_between/3)`; compare to rule threshold. Use UTC-normalised instants; period keys from `bucket/2`.
- Max hours/day/week: Accumulate hours per employee and period; compare to thresholds.
- Qualification-to-assignment: Join `TimesheetEntry` with `Certification`/`TrainingRecord` for role/location validity.
- Existence checks: `exists` at least one valid break in long shifts, etc.

## Agenda and Ordering

- Salience ordering:
  - 100: Compute per-period aggregates (hours, breaks)
  - 90: Apply rule checks (max hours, required breaks)
  - 80: Credential checks (training/certification presence/validity)
  - 30: Emit `ComplianceStatus` after collecting violations
- Determinism: sort emitted violations by (employee_id, code, period_key).

## Refraction

Do not duplicate identical violations; retract when underlying facts are corrected or expire.

## Edge Cases

- Partial data (missing breaks) → configurable severity (warning vs violation).
- Grace periods before/after expiry for certifications/training.
- Cross-jurisdiction shifts; apply stricter rule or location-of-work policy.

## Performance Targets (Initial)

- Support continuous updates from timekeeping; process small deltas sub-second.
- Emphasize alpha indexing by `employee_id`, `location`, and effective windows.

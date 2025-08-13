# Fact Schemas — Canonical WMEs and Derived Facts

This document defines canonical shapes for facts (WMEs) ingested by the engine and facts derived by rules. These schemas aim to be stable across use cases and optimized for Alpha/Beta discrimination.

## Conventions

- IDs: `id` is a stable string or integer. Referential fields end with `_id`.
- Time: Normalise instants to UTC `DateTime` at ingest; `Date` for all-day items; effective windows use `[effective_from, effective_to)` (to is exclusive).
- Keys: Discriminating keys used by Alpha indexes include `type`, `employee_id`, `location`, dates, and scenario identifiers.
- Precision: Monetary amounts use `Decimal`. DSL literals use `dec("12.34")` helper or numbers interpreted as Decimal by the compiler where unambiguous.
- Structs: Example Elixir structs shown for clarity; maps with equivalent keys are also accepted.

## Core WMEs

- Employee
  - Fields: `id`, `role`, `location`, `union`, `employment_type`, `effective_from`, `effective_to`
  - Example:
    - `%Employee{id: "e1", role: :nurse, location: "CA/SF", union: :u123, employment_type: :hourly, effective_from: ~U[2025-01-01 00:00:00Z], effective_to: nil}`
- TimesheetEntry
  - Fields: `id`, `employee_id`, `start_at`, `end_at`, `hours` (optional; computed if nil), `project_id`, `cost_center`, `approved?`
  - Example: `%TimesheetEntry{id: "t1", employee_id: "e1", start_at: dt("2025-02-10T09:00-08:00[America/Los_Angeles]"), end_at: dt("2025-02-10T17:30-08:00[America/Los_Angeles]"), project_id: "p1", cost_center: "c10", approved?: true}`
- PayRate
  - Fields: `id`, `employee_id` | `role`, `rate_type` (:hourly | :salary), `base_rate` (Decimal), `effective_from`, `effective_to`
  - Example: `%PayRate{id: "r1", role: :nurse, rate_type: :hourly, base_rate: D.new("45.00"), effective_from: dt("2025-01-01Z"), effective_to: nil}`
- OvertimePolicy
  - Fields: `id`, `jurisdiction` | `union`, `threshold_hours`, `multiplier`, `period` (:daily | :weekly), `effective_from`, `effective_to`
- Holiday
  - Fields: `id`, `date` (Date), `location`, `premium_multiplier`
- ShiftDifferential
  - Fields: `id`, `window` (%Time.Range or clock window), `multiplier` | `fixed`, `location` | `role`
- Deduction / EarningRule (optional)
  - Fields: `id`, `name`, `type`, `params`, `effective_from`, `effective_to`
- BreakRecord
  - Fields: `id`, `timesheet_entry_id`, `start_at`, `end_at`, `type`
- TrainingRecord
  - Fields: `id`, `employee_id`, `training_type`, `completed_at`, `expires_at`
- Certification
  - Fields: `id`, `employee_id`, `cert_type`, `issued_at`, `expires_at`
- PolicyRule
  - Fields: `id`, `rule_type`, `params`, `effective_from`, `effective_to`, `jurisdiction`, `role`
- LocationRegulation
  - Fields: `id`, `location`, `constraint_type`, `params`
- ScheduledShift
  - Fields: `id`, `employee_id` | `role`, `start_at`, `end_at`, `planned_hours`, `location`, `project_id`, `scenario_id`
- RateCard
  - Fields: `id`, `role` | `employee_id`, `base_rate`, `premiums`, `effective_from`, `effective_to`
- HolidayCalendar
  - Fields: `id`, `location`, `date`, `premium_multiplier`
- ProjectAssignment
  - Fields: `id`, `employee_id`, `project_id`, `cost_center`, `effective_from`, `effective_to`
- Scenario
  - Fields: `id`, `name`, `parameters`

## Derived Facts

- PayLine
  - Fields: `employee_id`, `period_key`, `component` (:base | :overtime | :premium), `hours`, `rate`, `amount`, `provenance`
- PayrollSummary
  - Fields: `employee_id`, `period_key`, `gross_amount`, `breakdown`
- ComplianceViolation
  - Fields: `employee_id`, `period_key`, `code`, `severity`, `details`, `provenance`
- ComplianceStatus
  - Fields: `employee_id`, `period_key`, `status` (:ok | :violations), `counts`
- CostEstimate
  - Fields: `scope` (:employee | :team | :project), `scope_id`, `bucket` (:day | :week), `hours`, `base_amount`, `overtime_amount`, `premium_amount`, `total_amount`, `scenario_id`, `provenance`
- EstimateSummary
  - Fields: `scenario_id`, `totals`
- Provenance (embedded)
  - Fields: `rule_id`, `token_signature`, `inputs` (list of `{type, id}`), `notes`

## Type Hints (Elixir)

The engine will ship structs, but user apps can use maps matching these keys. Example struct definitions:

```elixir
defmodule Facts.Employee do
  @enforce_keys [:id, :role, :location, :employment_type]
  defstruct [:id, :role, :location, :union, :employment_type, :effective_from, :effective_to]
end
defmodule Facts.TimesheetEntry do
  @enforce_keys [:id, :employee_id, :start_at, :end_at]
  defstruct [:id, :employee_id, :start_at, :end_at, :hours, :project_id, :cost_center, :approved?]
end
defmodule Facts.PayLine do
  @enforce_keys [:employee_id, :period_key, :component, :hours, :rate, :amount]
  defstruct [:employee_id, :period_key, :component, :hours, :rate, :amount, :provenance]
end
```

Note: This spec defines the target shapes for Alpha discrimination and Beta joins; the runtime may normalize inputs before matching (e.g., compute `hours` if missing).

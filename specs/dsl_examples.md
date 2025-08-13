# DSL Examples (v0)

Illustrative rules spanning multiple domains and layered scopes. Scope (tenant/general and any attributes like country/state/city/org_type) is metadata stored with the rule, not part of the DSL text.

imports
  use TimeCalcs: time_between, bucket
  use Money: decimal_mul, decimal_add

## General rules (examples)

```dsl
rule "us-daily-overtime" salience: 50 do
  when
    ts: TimesheetEntry(employee_id: e, hours: h, start_at: d)
    policy: OvertimePolicy(period: :daily, threshold_hours: t, multiplier: m)
    guard h > t
  then
    emit PayLine(employee_id: e, period_key: bucket(:day, d), component: :overtime, hours: h - t, rate: m)
end
```

```dsl
rule "sf-min-wage" salience: 60 do
  when
    shift: ScheduledShift(employee_id: e, start_at: s, end_at: f, location: "US/CA/SF", planned_hours: h)
    law: LocationRegulation(location: "US/CA/SF", constraint_type: :min_wage, params: p)
    rate: PayRate(employee_id: e, rate_type: :hourly, base_rate: r)
    guard r < p.min_wage
  then
    emit ComplianceViolation(employee_id: e, period_key: bucket(:day, s), code: "MIN_WAGE", severity: :high, details: "Base #{r} < #{p.min_wage}")
end
```

```dsl
rule "hospital-overtime-multiplier" salience: 55 do
  when
    pr: PayRate(employee_id: e, rate_type: :hourly, base_rate: r)
    emp: Employee(id: e, employment_type: :hourly, role: role)
    org: OrgType(name: :hospital)
    guard role in ["RN","MD","ER_TECH"]
  then
    emit RateAdjustment(employee_id: e, component: :overtime_multiplier, factor: 1.5)
end
```

## Tenant-specific rules (examples)

```dsl
rule "tenant-shift-premium-night" salience: 40 do
  when
    shift: ScheduledShift(employee_id: e, start_at: s, end_at: f, location: loc)
    guard s between DT'2025-01-01T22:00:00Z' and DT'2025-01-02T05:00:00Z'  # example; prefer explicit windows or precomputed flags
  then
    emit PayLine(employee_id: e, period_key: to_day(s), component: :premium, hours: time_between(s, f, :hours), rate: 1.2)
end
```

```dsl
rule "tenant-approved-timesheets-only" salience: 90 do
  when
    ts: TimesheetEntry(employee_id: e, approved?: a, start_at: s, end_at: f)
    guard a == true
  then
    emit ProcessingGate(kind: :timesheet_ok, employee_id: e, token: "#{ts.id}")
end
```

## Decision-table style

```dsl
rule "break-violation-daily" salience: 70 do
  when
    day: WorkDay(employee_id: e, total_hours: h, breaks_taken: b)
    guard h >= 6 and b < 1
  then
    emit ComplianceViolation(employee_id: e, period_key: day_key(day), code: "BREAK_MISS", severity: :medium, details: ">=6h requires 1 break")
end
```

## Temporal effective-dated joins

```dsl
rule "effective-payrate-selection" salience: 80 do
  when
    ts: TimesheetEntry(employee_id: e, start_at: s)
    rate: PayRate(employee_id: e, effective_from: ef, effective_to: et, base_rate: r)
    guard s >= ef and (et == nil or s < et)
  then
    emit SelectedRate(employee_id: e, at: s, rate: r)
end
```

## Weekly overtime (accumulate)

```dsl
rule "overtime-weekly-general" salience: 30 do
  when
    agg: accumulate from TimesheetEntry(employee_id: e, start_at: s, end_at: f, approved?: true)
         group_by e, bucket(:week, s)
         reduce hours: sum(time_between(s, f, :hours))
    policy: OvertimePolicy(period: :weekly, threshold_hours: t, multiplier: m)
    guard agg.hours > t
  then
    emit PayLine(employee_id: e, period_key: bucket(:week, s), component: :overtime, hours: agg.hours - t, rate: m)
end
```

```dsl
rule "overtime-weekly-tenant-exception" salience: 95 do
  when
    agg: accumulate from TimesheetEntry(employee_id: e, start_at: s, end_at: f, approved?: true)
         group_by e, bucket(:week, s)
         reduce hours: sum(time_between(s, f, :hours))
    policy: OvertimePolicy(period: :weekly, threshold_hours: t, multiplier: m)
    guard agg.hours > t - dec("4")
  then
    emit PayLine(employee_id: e, period_key: bucket(:week, s), component: :overtime, hours: agg.hours - (t - dec("4")), rate: m)
end
```

## Location layering (global base + city override)

```dsl
rule "holiday-premium-global" salience: 20 do
  when
    shift: ScheduledShift(employee_id: e, start_at: s, end_at: f, location: loc)
    hol: HolidayCalendar(location: base_location(loc), date: bucket(:day, s), premium_multiplier: m)
  then
    emit PayLine(employee_id: e, period_key: bucket(:day, s), component: :holiday_premium, hours: time_between(s, f, :hours), rate: m)
end
```

```dsl
rule "holiday-premium-city-override" salience: 85 do
  when
    shift: ScheduledShift(employee_id: e, start_at: s, end_at: f, location: "US/CA/SF")
    hol: HolidayCalendar(location: "US/CA/SF", date: bucket(:day, s), premium_multiplier: m)
  then
    emit PayLine(employee_id: e, period_key: bucket(:day, s), component: :holiday_premium, hours: time_between(s, f, :hours), rate: decimal_add(m, dec("0.25")))
end
```

## Org-type compliance

```dsl
rule "nurse-min-rest-between-shifts" salience: 65 do
  when
    prev: ScheduledShift(employee_id: e, end_at: f, role: "RN")
    next: ScheduledShift(employee_id: e, start_at: s, role: "RN")
    guard s > f and time_between(f, s, :hours) < dec("8")
  then
    emit ComplianceViolation(employee_id: e, period_key: bucket(:day, s), code: "REST_SHORTFALL", severity: :high, details: "Less than 8h between shifts")
end
```

## Cost estimation

```dsl
rule "estimate-overtime-bucket" salience: 25 do
  when
    est: CostEstimate(scope: :employee, scope_id: e, bucket: b, hours: h, base_amount: base)
    policy: OvertimePolicy(period: :weekly, threshold_hours: t, multiplier: m)
    guard h > t
  then
    emit CostEstimate(scope: :employee, scope_id: e, bucket: b, overtime_amount: (h - t) * m, total_amount: base + (h - t) * m)
end
```

## Notes

- Helper functions like `to_day/1`, `hour/1`, `hours_between/3`, `duration_hours/2`, `base_location/1` are intended built-ins or compiled intrinsics. Replace with explicit precomputed facts if unavailable.
- Keep rule ids unique across bundles and tenant rules; use salience or narrowed guards for overrides.

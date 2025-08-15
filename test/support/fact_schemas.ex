defmodule RulesEngineTest.Support.FactSchemas do
  @moduledoc """
  Test fact schema registry providing schemas used in test fixtures.

  This module contains schemas for all fact types used across the test suite,
  extracted from the original built-in fact schemas to support test validation.
  """

  @doc """
  Returns the test fact schemas used across the test suite.
  """
  @spec schemas() :: map()
  def schemas do
    %{
      # Core WMEs for payroll/compliance testing
      "Employee" => %{
        "fields" => [
          "id",
          "role",
          "location",
          "union",
          "employment_type",
          "effective_from",
          "effective_to"
        ]
      },
      "TimesheetEntry" => %{
        "fields" => [
          "id",
          "employee_id",
          "start_at",
          "end_at",
          "hours",
          "project_id",
          "cost_center",
          "approved?"
        ]
      },
      "PayRate" => %{
        "fields" => [
          "id",
          "employee_id",
          "role",
          "rate_type",
          "base_rate",
          "effective_from",
          "effective_to"
        ]
      },
      "OvertimePolicy" => %{
        "fields" => [
          "id",
          "jurisdiction",
          "union",
          "threshold_hours",
          "multiplier",
          "period",
          "effective_from",
          "effective_to"
        ]
      },
      "Holiday" => %{
        "fields" => [
          "id",
          "date",
          "location",
          "premium_multiplier"
        ]
      },
      "ShiftDifferential" => %{
        "fields" => [
          "id",
          "window",
          "multiplier",
          "fixed",
          "location",
          "role"
        ]
      },
      "Jurisdiction" => %{
        "fields" => [
          "id",
          "code",
          "min_wage",
          "overtime_multiplier",
          "effective_from",
          "effective_to"
        ]
      },
      "Shift" => %{
        "fields" => [
          "id",
          "employee_id",
          "start_at",
          "end_at",
          "hours",
          "hourly_rate",
          "date",
          "jurisdiction",
          "location"
        ]
      },
      "BreakRecord" => %{
        "fields" => [
          "id",
          "timesheet_entry_id",
          "start_at",
          "end_at",
          "type"
        ]
      },
      "TrainingRecord" => %{
        "fields" => [
          "id",
          "employee_id",
          "training_type",
          "completed_at",
          "expires_at"
        ]
      },
      "Certification" => %{
        "fields" => [
          "id",
          "employee_id",
          "cert_type",
          "issued_at",
          "expires_at"
        ]
      },

      # Derived Facts
      "PayLine" => %{
        "fields" => [
          "employee_id",
          "period_key",
          "component",
          "hours",
          "rate",
          "amount",
          "provenance"
        ]
      },
      "PayrollSummary" => %{
        "fields" => [
          "employee_id",
          "period_key",
          "gross_amount",
          "breakdown"
        ]
      },
      "ComplianceViolation" => %{
        "fields" => [
          "employee_id",
          "period_key",
          "kind",
          "code",
          "severity",
          "details",
          "deficit_per_hour",
          "provenance"
        ]
      },
      "ComplianceStatus" => %{
        "fields" => [
          "employee_id",
          "period_key",
          "status",
          "counts"
        ]
      },
      "CostEstimate" => %{
        "fields" => [
          "scope",
          "scope_id",
          "bucket",
          "hours",
          "base_amount",
          "overtime_amount",
          "premium_amount",
          "total_amount",
          "scenario_id",
          "provenance"
        ]
      },
      "HoursTotal" => %{
        "fields" => [
          "employee_id",
          "hours"
        ]
      },
      "HoursAgg" => %{
        "fields" => [
          "employee_id",
          "hours"
        ]
      },

      # Test/example types for validation tests
      "User" => %{
        "fields" => [
          "name",
          "sign_in_at",
          "roles"
        ]
      },
      "Audit" => %{
        "fields" => [
          "user"
        ]
      },
      "A" => %{
        "fields" => [
          "id",
          "a_id",
          "x",
          "y",
          "z"
        ]
      },
      "B" => %{
        "fields" => [
          "id",
          "a_id"
        ]
      },
      "C" => %{
        "fields" => [
          "id",
          "a_id"
        ]
      },
      "Out" => %{
        "fields" => [
          "id",
          "x",
          "y",
          "msg",
          "result"
        ]
      },
      "Result" => %{
        "fields" => [
          "total_hours",
          "emp",
          "employee"
        ]
      }
    }
  end
end

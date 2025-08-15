defmodule RulesEngine.FactSchemas do
  @moduledoc """
  Built-in fact schema registry providing canonical fact schemas per specs/fact_schemas.md.

  This module defines the standard fact types used across the rules engine, including
  core WMEs (Working Memory Elements) and derived facts produced by rules.
  """

  @doc """
  Returns the canonical fact schemas as defined in specs/fact_schemas.md.
  Each schema contains field definitions and metadata for validation.
  """
  @spec canonical_schemas() :: map()
  def canonical_schemas do
    %{
      # Core WMEs
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

      # Test/example types
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
          "a_id"
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

  @doc """
  Get schema for a specific fact type.
  Returns nil if the type is not found in the canonical schemas.
  """
  @spec get_schema(String.t()) :: map() | nil
  def get_schema(fact_type) when is_binary(fact_type) do
    Map.get(canonical_schemas(), fact_type)
  end

  @doc """
  Get allowed fields for a specific fact type.
  Returns empty list if the type is not found.
  """
  @spec get_fields(String.t()) :: [String.t()]
  def get_fields(fact_type) when is_binary(fact_type) do
    case get_schema(fact_type) do
      %{"fields" => fields} -> fields
      _ -> []
    end
  end

  @doc """
  Validate if a field is allowed for a given fact type.
  """
  @spec field_allowed?(String.t(), String.t()) :: boolean()
  def field_allowed?(fact_type, field_name) when is_binary(fact_type) and is_binary(field_name) do
    field_name in get_fields(fact_type)
  end
end

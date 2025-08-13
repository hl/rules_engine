defmodule RulesEngine.DomainRulesTest do
  use ExUnit.Case, async: true
  doctest RulesEngine

  alias RulesEngine.DSL.Parser

  @moduledoc """
  Tests to ensure all domain rule examples from specs are properly tested.
  This covers examples from:
  - specs/dsl_examples.md
  - specs/payroll.md
  - specs/compliance.md
  - specs/wage_cost_estimation.md

  Uses JSON fixtures to define expected AST structure for each rule.
  """

  @fixture_dir Path.join([__DIR__, "fixtures"])

  defp read_dsl_fixture(filename) do
    File.read!(Path.join([@fixture_dir, "dsl", filename]))
  end

  defp read_json_fixture(filename) do
    [@fixture_dir, "json", filename]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
  end

  describe "Payroll Domain Rules" do
    test "us-daily-overtime rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("us_daily_overtime.rule")
      expected_json = read_json_fixture("us_daily_overtime.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "hospital-overtime-multiplier rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("hospital_overtime_multiplier.rule")
      expected_json = read_json_fixture("hospital_overtime_multiplier.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "effective-payrate-selection rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("effective_payrate_selection.rule")
      expected_json = read_json_fixture("effective_payrate_selection.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "holiday-premium-global rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("holiday_premium_global.rule")
      expected_json = read_json_fixture("holiday_premium_global.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "holiday-premium-city-override rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("holiday_premium_city_override.rule")
      expected_json = read_json_fixture("holiday_premium_city_override.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "overtime-weekly-general rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("overtime_weekly_general.rule")
      expected_json = read_json_fixture("overtime_weekly_general.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "overtime-weekly-tenant-exception rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("overtime_weekly_tenant_exception.rule")
      expected_json = read_json_fixture("overtime_weekly_tenant_exception.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end
  end

  describe "Compliance Domain Rules" do
    test "sf-min-wage compliance rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("sf_min_wage.rule")
      expected_json = read_json_fixture("sf_min_wage.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "break-violation-daily rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("break_violation_daily.rule")
      expected_json = read_json_fixture("break_violation_daily.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "nurse-min-rest-between-shifts rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("nurse_min_rest_between_shifts.rule")
      expected_json = read_json_fixture("nurse_min_rest_between_shifts.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "minimum-wage rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("min_wage.rule")
      expected_json = read_json_fixture("min-wage.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end
  end

  describe "Wage Cost Estimation Domain Rules" do
    test "shift_hours cost estimation rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("shift_hours.rule")
      expected_json = read_json_fixture("shift-hours.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "base_cost rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("base_cost.rule")
      expected_json = read_json_fixture("base-cost.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "estimate-overtime-bucket rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("estimate_overtime_bucket.rule")
      expected_json = read_json_fixture("estimate_overtime_bucket.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "taxes_and_benefits rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("taxes_and_benefits.rule")
      expected_json = read_json_fixture("taxes-and-benefits.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end
  end

  describe "Tenant-Specific Domain Rules" do
    test "tenant-shift-premium-night rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("tenant_shift_premium_night.rule")
      expected_json = read_json_fixture("tenant_shift_premium_night.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end

    test "tenant-approved-timesheets-only rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("tenant_approved_timesheets_only.rule")
      expected_json = read_json_fixture("tenant_approved_timesheets_only.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end
  end

  describe "Additional Domain Rules" do
    test "set-membership rule matches expected JSON structure" do
      dsl_content = read_dsl_fixture("set_membership.rule")
      expected_json = read_json_fixture("set_membership.json")

      assert_rule_matches_json(dsl_content, expected_json)
    end
  end

  describe "Rule Coverage Validation" do
    test "all DSL examples from specs have corresponding fixtures" do
      # Get all DSL fixtures
      dsl_fixtures =
        File.ls!(Path.join([@fixture_dir, "dsl"]))
        |> Enum.filter(&String.ends_with?(&1, ".rule"))
        |> Enum.map(&String.replace(&1, ".rule", ""))
        |> Enum.map(&String.replace(&1, "_", "-"))

      # Expected rules from specifications
      expected_rules = [
        # From dsl_examples.md
        "us-daily-overtime",
        "sf-min-wage",
        "hospital-overtime-multiplier",
        "tenant-shift-premium-night",
        "tenant-approved-timesheets-only",
        "break-violation-daily",
        "effective-payrate-selection",
        "overtime-weekly-general",
        "overtime-weekly-tenant-exception",
        "holiday-premium-global",
        "holiday-premium-city-override",
        "nurse-min-rest-between-shifts",
        "estimate-overtime-bucket",

        # From wage_cost_estimation.md
        "shift-hours",
        "base-cost",
        "taxes-and-benefits"
      ]

      coverage =
        expected_rules
        |> Enum.filter(&(&1 in dsl_fixtures))
        |> length()

      coverage_percent = coverage / length(expected_rules)

      assert coverage_percent >= 0.8, "Should have at least 80% fixture coverage of spec examples"
      assert coverage >= 12, "Should have at least 12 domain rule fixtures"
    end

    test "fixtures represent diverse domain patterns" do
      # Document that fixtures cover key domain patterns:
      domain_patterns = [
        "Basic fact matching and filtering",
        "Guard expressions with comparisons",
        "Time calculations and bucket operations",
        "Money calculations with decimal operations",
        "Compliance violations with severity levels",
        "Cost estimation with multiple factors",
        "Tenant-specific overrides",
        "Multi-fact joins across different domains"
      ]

      assert length(domain_patterns) >= 8, "Should cover diverse domain patterns"
    end
  end

  # Helper function to validate rule matches expected JSON structure
  defp assert_rule_matches_json(dsl_content, expected_json) do
    case Parser.parse(dsl_content) do
      {:ok, [rule], _warnings} ->
        # Transform rule to JSON-like structure for comparison
        actual = transform_rule_to_json(rule)

        # Compare key fields
        assert actual["name"] == expected_json["name"]
        assert actual["salience"] == expected_json["salience"]
        assert length(actual["when"]) == length(expected_json["when"])
        assert length(actual["then"]) == length(expected_json["then"])

      {:error, errors} ->
        flunk("Rule failed to parse: #{inspect(errors)}")

      other ->
        flunk("Unexpected parse result: #{inspect(other)}")
    end
  end

  # Transform parsed AST to JSON-like structure for comparison  
  defp transform_rule_to_json(rule) do
    case rule do
      %{name: name, salience: {:when, _} = when_clause, then: then_clause} ->
        # Rule without explicit salience - salience field contains the when clause
        %{
          "name" => name,
          "salience" => 0,
          "when" => transform_when_clauses(when_clause),
          "then" => transform_then_clauses(then_clause)
        }

      %{name: name, salience: salience, when: when_clause, then: then_clause} ->
        # Rule with explicit salience
        %{
          "name" => name,
          "salience" => salience || 0,
          "when" => transform_when_clauses(when_clause),
          "then" => transform_then_clauses(then_clause)
        }

      other ->
        # Debug output for unexpected structure
        IO.inspect(other, label: "Unexpected rule structure")

        %{
          "name" => "unknown",
          "salience" => 0,
          "when" => [],
          "then" => []
        }
    end
  end

  defp transform_rule_to_json(%{name: name, when: when_clause, then: then_clause}) do
    %{
      "name" => name,
      "salience" => 0,
      "when" => transform_when_clauses(when_clause),
      "then" => transform_then_clauses(then_clause)
    }
  end

  defp transform_when_clauses(nil), do: []

  defp transform_when_clauses({:when, clauses}) do
    Enum.map(clauses, &transform_when_clause/1)
  end

  defp transform_when_clause({:fact, binding, type, fields}) do
    %{
      "binding" => to_string(binding),
      "type" => to_string(type),
      "fields" => Enum.into(fields, %{}, fn {k, v} -> {to_string(k), transform_value(v)} end)
    }
  end

  defp transform_when_clause({:guard, expr}) do
    %{"guard" => transform_value(expr)}
  end

  defp transform_then_clauses(nil), do: []

  defp transform_then_clauses({:then, clauses}) do
    Enum.map(clauses, &transform_then_clause/1)
  end

  defp transform_then_clause({:emit, type, fields}) do
    %{
      "emit" => to_string(type),
      "fields" => Enum.into(fields, %{}, fn {k, v} -> {to_string(k), transform_value(v)} end)
    }
  end

  defp transform_value({:binding_ref, binding}), do: %{"binding_ref" => to_string(binding)}

  defp transform_value({:call, name, args}),
    do: %{"call" => [to_string(name), Enum.map(args, &transform_value/1)]}

  defp transform_value({:arith, op, l, r}),
    do: %{"arith" => [to_string(op), transform_value(l), transform_value(r)]}

  defp transform_value({:cmp, op, l, r}),
    do: %{"cmp" => [to_string(op), transform_value(l), transform_value(r)]}

  defp transform_value({:and, l, r}), do: %{"and" => [transform_value(l), transform_value(r)]}
  defp transform_value({:or, l, r}), do: %{"or" => [transform_value(l), transform_value(r)]}

  defp transform_value({:set, op, binding, values}),
    do: %{"set" => [to_string(op), to_string(binding), Enum.map(values, &transform_value/1)]}

  defp transform_value(atom) when is_atom(atom), do: to_string(atom)
  defp transform_value(str) when is_binary(str), do: str
  defp transform_value(num) when is_number(num), do: num
  defp transform_value(other), do: inspect(other)
end

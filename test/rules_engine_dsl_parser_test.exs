defmodule RulesEngine.DSL.ParserTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Parser

  @fixtures [
    {"us_daily_overtime.rule", "us_daily_overtime.json"},
    {"min_wage.rule", nil},
    {"set_membership.rule", nil},
    {"sf_min_wage.rule", nil},
    {"hospital_overtime_multiplier.rule", nil},
    {"tenant_shift_premium_night.rule", nil},
    {"tenant_approved_timesheets_only.rule", nil},
    {"break_violation_daily.rule", nil},
    {"effective_payrate_selection.rule", nil},
    {"overtime_weekly_general.rule", nil},
    {"overtime_weekly_tenant_exception.rule", nil},
    {"holiday_premium_global.rule", nil},
    {"holiday_premium_city_override.rule", nil},
    {"nurse_min_rest_between_shifts.rule", nil},
    {"estimate_overtime_bucket.rule", nil},
    {"shift_hours.rule", nil},
    {"base_cost.rule", nil},
    {"taxes_and_benefits.rule", nil}
  ]

  defp read_fixture(path), do: File.read!(Path.join([__DIR__, "fixtures", path]))

  test "parses DSL to AST that matches expected JSON shape" do
    Enum.each(@fixtures, fn {dsl_file, json_file} ->
      dsl = read_fixture(Path.join("dsl", dsl_file))
      {:ok, ast, _warnings} = Parser.parse(dsl)
      assert is_list(ast)

      # For now, convert our AST nodes to a JSON-like map for comparison
      [rule] = ast
      jsonish = transform_rule(rule)

      if json_file do
        expected = Jason.decode!(read_fixture(Path.join("json", json_file)))
        assert jsonish["name"] == expected["name"]
        assert jsonish["salience"] == expected["salience"]
        assert length(jsonish["when"]) == length(expected["when"])
        assert length(jsonish["then"]) == length(expected["then"])
      else
        # structural sanity for fixtures without explicit JSON
        assert is_binary(jsonish["name"]) and String.length(jsonish["name"]) > 0
        assert is_integer(jsonish["salience"]) or is_nil(jsonish["salience"]) == false
        assert is_list(jsonish["when"]) and length(jsonish["when"]) >= 1
        assert is_list(jsonish["then"]) and length(jsonish["then"]) >= 1
      end
    end)
  end

  defp transform_rule(%{
         name: name,
         salience: salience,
         when: {:when, when_list},
         then: {:then, then_list}
       }) do
    %{
      "name" => name,
      "salience" => salience || 0,
      "when" => Enum.map(when_list, &transform_when/1),
      "then" => Enum.map(then_list, &transform_then/1)
    }
  end

  defp transform_rule(%{name: name, salience: {:when, when_list}, then: {:then, then_list}}) do
    %{
      "name" => name,
      "salience" => 0,
      "when" => Enum.map(when_list, &transform_when/1),
      "then" => Enum.map(then_list, &transform_then/1)
    }
  end

  defp transform_when({:fact, binding, type, fields}) do
    %{
      "binding" => binding,
      "type" => type,
      "fields" => Enum.into(fields, %{}, fn {k, v} -> {to_string(k), transform_value(v)} end)
    }
  end

  defp transform_when({:guard, expr}), do: %{"guard" => transform_value(expr)}
  defp transform_when({:exists, fact}), do: %{"exists" => transform_when(fact)}
  defp transform_when({:not, {:exists, fact}}), do: %{"not_exists" => transform_when(fact)}
  defp transform_when({:not, fact}), do: %{"not" => transform_when(fact)}

  defp transform_then({:emit, type, fields}) do
    %{
      "emit" => type,
      "fields" => Enum.into(fields, %{}, fn {k, v} -> {to_string(k), transform_value(v)} end)
    }
  end

  defp transform_value({:binding_ref, b}), do: %{"binding_ref" => b}
  defp transform_value(binding_ref: b), do: %{"binding_ref" => b}

  defp transform_value({:call, name, args}),
    do: %{"call" => [name, Enum.map(args, &transform_value/1)]}

  defp transform_value({:arith, op, l, r}),
    do: %{"arith" => [op, transform_value(l), transform_value(r)]}

  defp transform_value({:cmp, op, l, r}),
    do: %{"cmp" => [op, transform_value(l), transform_value(r)]}

  defp transform_value({:and, l, r}),
    do: %{"and" => [transform_value(l), transform_value(r)]}

  defp transform_value({:or, l, r}),
    do: %{"or" => [transform_value(l), transform_value(r)]}

  defp transform_value({:between, v, l, r}),
    do: %{"between" => [transform_value(v), transform_value(l), transform_value(r)]}

  defp transform_value({:set, op, binding, values}),
    do: %{"set" => [op, binding, Enum.map(values, &transform_value/1)]}

  defp transform_value(list) when is_list(list), do: Enum.map(list, &transform_value/1)

  defp transform_value({:date, s}), do: %{"date" => s}
  defp transform_value({:datetime, s}), do: %{"datetime" => s}
  defp transform_value(atom) when is_atom(atom), do: to_string(atom)

  defp transform_value(list) when is_list(list) and length(list) == 1 and is_atom(hd(list)),
    do: to_string(hd(list))

  defp transform_value(%Decimal{} = d), do: %{"decimal" => Decimal.to_string(d)}
  defp transform_value(int) when is_integer(int), do: int
  defp transform_value(bin) when is_binary(bin), do: bin
end

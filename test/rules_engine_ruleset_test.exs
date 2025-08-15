defmodule RulesEngine.RulesetTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "t-456"
  @now DateTime.from_naive!(~N[2025-01-01 00:00:00], "Etc/UTC")

  test "multiple DSL files compile and appear together in IR rules" do
    base = Path.join([__DIR__, "fixtures", "dsl"])

    sources =
      [
        Path.join(base, "accumulate_total_hours.rule"),
        Path.join(base, "sf_min_wage.rule")
      ]
      |> Enum.map(&File.read!/1)

    program = Enum.join(sources, "\n\n")

    {:ok, ir} = Compiler.parse_and_compile(@tenant, program, %{now: @now})

    # Validate against specs schema
    schema_path = Path.expand("../specs/ir.schema.json", __DIR__)
    schema = Jason.decode!(File.read!(schema_path))
    {:ok, root} = JSV.build(schema)
    assert {:ok, _casted} = JSV.validate(ir, root)

    names = ir["rules"] |> Enum.map(& &1["name"]) |> MapSet.new()
    assert MapSet.subset?(MapSet.new(["accumulate-total-hours", "sf-min-wage"]), names)

    saliences = ir["rules"] |> Enum.into(%{}, fn r -> {r["name"], r["salience"]} end)
    assert saliences["accumulate-total-hours"] == 70
    assert saliences["sf-min-wage"] == 60
  end

  test "authoring-level ruleset fixture matches intended structure (non-compiled)" do
    # This is a documentation/contract check: authoring ruleset fixture shape
    path = Path.join([__DIR__, "fixtures", "json", "ruleset-basic.json"])
    {:ok, json} = File.read(path)
    {:ok, decoded} = Jason.decode(json)

    assert is_map(decoded)
    assert Map.has_key?(decoded, "rules")
    assert is_list(decoded["rules"]) and length(decoded["rules"]) >= 2

    rule_names = decoded["rules"] |> Enum.map(& &1["name"]) |> MapSet.new()
    assert MapSet.subset?(MapSet.new(["accumulate-total-hours", "sf-min-wage"]), rule_names)

    # Ensure rules use authoring shape keys
    for rule <- decoded["rules"] do
      assert Map.has_key?(rule, "when")
      assert Map.has_key?(rule, "then")
      refute Map.has_key?(rule, "bindings")
      refute Map.has_key?(rule, "actions")
    end
  end
end

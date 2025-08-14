defmodule RulesEngine.DSL.E2EIRTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "t-123"
  @now DateTime.from_naive!(~N[2025-01-01 00:00:00], "Etc/UTC")

  test "DSL compiles to IR that validates against schema" do
    source = File.read!(Path.join([__DIR__, "fixtures", "dsl", "us_daily_overtime.rule"]))

    {:ok, ir} = Compiler.parse_and_compile(@tenant, source, %{now: @now})

    # Validate against specs schema
    schema_path = Path.expand("../specs/ir.schema.json", __DIR__)
    schema = Jason.decode!(File.read!(schema_path))
    {:ok, root} = JSV.build(schema)
    assert {:ok, _casted} = JSV.validate(ir, root)

    # Basic sanity: required fields present
    assert ir["version"] == "v1"
    assert ir["tenant_id"] == @tenant
    assert is_list(ir["rules"]) and length(ir["rules"]) >= 1
    assert Map.has_key?(ir, "network")
  end
end

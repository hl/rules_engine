defmodule RulesEngine.ValidationBuiltInSchemasTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler
  alias RulesEngine.FactSchemas

  @tenant "test"

  test "built-in schemas are used by default" do
    # Use a fixture that should pass with canonical schemas
    source =
      File.read!(Path.join([__DIR__, "fixtures", "dsl", "schema_validation_canonical.rule"]))

    # Should pass - all fields are in canonical schemas
    assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, source)
  end

  test "unknown field in canonical fact type fails validation by default" do
    # Use a fixture with invalid fields
    source =
      File.read!(Path.join([__DIR__, "fixtures", "dsl", "schema_validation_invalid_field.rule"]))

    assert {:error, errors} = Compiler.parse_and_compile(@tenant, source)

    assert Enum.any?(
             errors,
             &(&1.code == :unknown_field and &1.message =~ "invalid_field for Employee")
           )
  end

  test "fact schema registry provides canonical schemas" do
    schemas = FactSchemas.canonical_schemas()

    # Core WMEs should be present
    assert Map.has_key?(schemas, "Employee")
    assert Map.has_key?(schemas, "TimesheetEntry")
    assert Map.has_key?(schemas, "PayLine")

    # Employee should have expected fields
    employee_fields = FactSchemas.get_fields("Employee")
    assert "id" in employee_fields
    assert "role" in employee_fields
    assert "location" in employee_fields
  end

  test "schema validation can be disabled explicitly" do
    # Create a rule with invalid fields
    source =
      File.read!(Path.join([__DIR__, "fixtures", "dsl", "schema_validation_invalid_field.rule"]))

    # Should pass when schemas are disabled
    assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, source, %{fact_schemas: false})
  end
end

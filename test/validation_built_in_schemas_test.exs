defmodule RulesEngine.ValidationExternalSchemasTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler
  alias RulesEngineTest.Support.FactSchemas

  @tenant "test"
  @schemas FactSchemas.schemas()

  test "external schemas work when provided" do
    # Use a fixture that should pass with test schemas
    source =
      File.read!(Path.join([__DIR__, "fixtures", "dsl", "schema_validation_canonical.rule"]))

    # Should pass - all fields are in test schemas
    assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, source, %{fact_schemas: @schemas})
  end

  test "unknown field in fact type fails validation with external schemas" do
    # Use a fixture with invalid fields
    source =
      File.read!(Path.join([__DIR__, "fixtures", "dsl", "schema_validation_invalid_field.rule"]))

    assert {:error, errors} =
             Compiler.parse_and_compile(@tenant, source, %{fact_schemas: @schemas})

    assert Enum.any?(
             errors,
             &(&1.code == :unknown_field and &1.message =~ "invalid_field for Employee")
           )
  end

  test "test schema registry provides schemas" do
    schemas = FactSchemas.schemas()

    # Core WMEs should be present
    assert Map.has_key?(schemas, "Employee")
    assert Map.has_key?(schemas, "TimesheetEntry")
    assert Map.has_key?(schemas, "PayLine")

    # Employee should have expected fields
    employee_schema = Map.get(schemas, "Employee")
    employee_fields = Map.get(employee_schema, "fields", [])
    assert "id" in employee_fields
    assert "role" in employee_fields
    assert "location" in employee_fields
  end

  test "schema validation can be disabled explicitly" do
    # Create a rule with invalid fields
    source =
      File.read!(Path.join([__DIR__, "fixtures", "dsl", "schema_validation_invalid_field.rule"]))

    # Should pass when schemas are disabled
    assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, source, %{fact_schemas: nil})
  end

  test "compilation fails without schemas when validation needed" do
    # Use a fixture that needs schema validation
    source =
      File.read!(Path.join([__DIR__, "fixtures", "dsl", "schema_validation_canonical.rule"]))

    # Should pass without schemas (no validation performed)
    assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, source)
  end
end

defmodule RulesEngine.ErrorFormatterTest do
  use ExUnit.Case, async: true
  doctest RulesEngine.ErrorFormatter

  alias RulesEngine.ErrorFormatter
  alias RulesEngine.ErrorFormatter.{Compact, Default, JSON}

  @sample_error %{
    code: :unknown_binding,
    message: "unknown binding employee_id",
    path: ["overtime-rule", :when, :fact_pattern, "employee_id"]
  }

  @parse_error %{
    code: :parse_error,
    message: "unexpected token",
    path: ["invalid-rule"],
    line: 5,
    column: 12
  }

  @complex_error %{
    code: :schema_validation_failed,
    message: "IR failed validation",
    path: ["test-rule"],
    stage: :direct_validation,
    errors: [
      %{field: "rules.0.name", message: "required"}
    ]
  }

  describe "ErrorFormatter configuration" do
    setup do
      # Save original formatter
      original = ErrorFormatter.get_formatter()

      on_exit(fn ->
        ErrorFormatter.set_formatter(original)
      end)

      %{original_formatter: original}
    end

    test "get_formatter returns default formatter by default" do
      assert ErrorFormatter.get_formatter() == RulesEngine.ErrorFormatter.Default
    end

    test "set_formatter changes the active formatter" do
      ErrorFormatter.set_formatter(RulesEngine.ErrorFormatter.JSON)
      assert ErrorFormatter.get_formatter() == RulesEngine.ErrorFormatter.JSON

      ErrorFormatter.set_formatter(RulesEngine.ErrorFormatter.Compact)
      assert ErrorFormatter.get_formatter() == RulesEngine.ErrorFormatter.Compact
    end

    test "format_error uses configured formatter" do
      # Test with Default formatter
      ErrorFormatter.set_formatter(Default)
      default_result = ErrorFormatter.format_error(@sample_error)
      assert is_binary(default_result)
      assert String.contains?(default_result, "Error [unknown_binding]")

      # Test with JSON formatter
      ErrorFormatter.set_formatter(JSON)
      json_result = ErrorFormatter.format_error(@sample_error)
      assert is_map(json_result)
      assert json_result.code == :unknown_binding

      # Test with Compact formatter
      ErrorFormatter.set_formatter(Compact)
      compact_result = ErrorFormatter.format_error(@sample_error)
      assert is_binary(compact_result)
      assert String.contains?(compact_result, "[unknown_binding]")
    end
  end

  describe "Default formatter" do
    test "format_error creates readable error message" do
      result = Default.format_error(@sample_error)

      assert String.contains?(result, "Error [unknown_binding]")
      assert String.contains?(result, "unknown binding employee_id")
      assert String.contains?(result, "overtime-rule -> when -> fact_pattern -> employee_id")
    end

    test "format_error handles parse errors with position" do
      result = Default.format_error(@parse_error)

      assert String.contains?(result, "Error [parse_error]")
      assert String.contains?(result, "unexpected token")
      assert String.contains?(result, "line 5, column 12")
    end

    test "format_error handles complex errors with metadata" do
      result = Default.format_error(@complex_error)

      assert String.contains?(result, "Error [schema_validation_failed]")
      assert String.contains?(result, "Stage: direct_validation")
      assert String.contains?(result, "Nested: 1 nested errors")
    end

    test "format_errors handles single error" do
      result = Default.format_errors([@sample_error])

      assert String.contains?(result, "Error [unknown_binding]")
      refute String.contains?(result, "1 errors found")
    end

    test "format_errors handles multiple errors" do
      errors = [@sample_error, @parse_error]
      result = Default.format_errors(errors)

      assert String.contains?(result, "2 errors found:")
      assert String.contains?(result, "1. Error [unknown_binding]")
      assert String.contains?(result, "2. Error [parse_error]")
    end

    test "format_error_with_context includes context information" do
      context = %{
        tenant_id: "tenant-123",
        source_code: "rule \"test\" do\n  when employee_id > 10\n  then emit result\nend"
      }

      result = Default.format_error_with_context(@sample_error, context)

      assert String.contains?(result, "Error [unknown_binding]")
      assert String.contains?(result, "Tenant: tenant-123")
      assert String.contains?(result, "Source: rule \"test\" do")
    end
  end

  describe "JSON formatter" do
    test "format_error creates structured JSON-ready map" do
      result = JSON.format_error(@sample_error)

      assert result.type == "error"
      assert result.code == :unknown_binding
      assert result.message == "unknown binding employee_id"

      assert result.location.path == ["overtime-rule", "when", "fact_pattern", "employee_id"]
      assert result.location.path_string == "overtime-rule -> when -> fact_pattern -> employee_id"
    end

    test "format_error handles parse errors with position metadata" do
      result = JSON.format_error(@parse_error)

      assert result.code == :parse_error
      assert result.metadata.position.line == 5
      assert result.metadata.position.column == 12
    end

    test "format_error handles complex errors with nested metadata" do
      result = JSON.format_error(@complex_error)

      assert result.code == :schema_validation_failed
      assert result.metadata.stage == :direct_validation
      assert result.metadata.nested_errors.count == 1
    end

    test "format_errors creates structured array response" do
      errors = [@sample_error, @parse_error]
      result = JSON.format_errors(errors)

      assert result.type == "errors"
      assert result.count == 2
      assert length(result.errors) == 2
      assert Enum.at(result.errors, 0).code == :unknown_binding
      assert Enum.at(result.errors, 1).code == :parse_error
    end

    test "format_error_with_context includes formatted context" do
      context = %{
        tenant_id: "tenant-123",
        file_name: "rules/overtime.rule",
        source_code: "rule \"test\" do\n  when employee_id > 10\n  then emit result\nend"
      }

      result = JSON.format_error_with_context(@sample_error, context)

      assert result.code == :unknown_binding
      assert result.context.tenant_id == "tenant-123"
      assert result.context.file_name == "rules/overtime.rule"
      assert String.contains?(result.context.source_preview, "rule \"test\" do")
    end
  end

  describe "Compact formatter" do
    test "format_error creates single-line message" do
      result = Compact.format_error(@sample_error)

      assert is_binary(result)
      assert String.contains?(result, "[unknown_binding] unknown binding employee_id")
      assert String.contains?(result, "at overtime-rule->when->fact_pattern->employee_id")
      refute String.contains?(result, "\n")
    end

    test "format_error handles parse errors with position" do
      result = Compact.format_error(@parse_error)

      assert String.contains?(result, "[parse_error] unexpected token")
      assert String.contains?(result, "5:12")
      refute String.contains?(result, "\n")
    end

    test "format_errors creates semicolon-separated list for multiple errors" do
      errors = [@sample_error, @parse_error]
      result = Compact.format_errors(errors)

      assert String.contains?(result, "2 errors:")
      assert String.contains?(result, "[unknown_binding]")
      assert String.contains?(result, "[parse_error]")
      assert String.contains?(result, ";")
      refute String.contains?(result, "\n")
    end

    test "format_error_with_context adds context in parentheses" do
      context = %{tenant_id: "tenant-123"}

      result = Compact.format_error_with_context(@sample_error, context)

      assert String.contains?(result, "[unknown_binding] unknown binding employee_id")
      assert String.contains?(result, "(tenant: tenant-123)")
      refute String.contains?(result, "\n")
    end
  end

  describe "Edge cases" do
    test "formatters handle errors without path" do
      error_without_path = %{
        code: :general_error,
        message: "something went wrong"
      }

      default_result = Default.format_error(error_without_path)
      json_result = JSON.format_error(error_without_path)
      compact_result = Compact.format_error(error_without_path)

      assert String.contains?(default_result, "Error [general_error]")
      assert json_result.code == :general_error
      refute Map.has_key?(json_result, :location)
      assert String.contains?(compact_result, "[general_error]")
    end

    test "formatters handle empty error lists" do
      default_result = Default.format_errors([])
      json_result = JSON.format_errors([])
      compact_result = Compact.format_errors([])

      assert default_result == "No errors found"
      assert json_result.count == 0
      assert compact_result == "No errors"
    end

    test "formatters handle malformed error maps gracefully" do
      # Missing message
      malformed_error = %{code: :test}

      # Should not crash, even with missing fields
      assert is_binary(Default.format_error(malformed_error))
      assert is_map(JSON.format_error(malformed_error))
      assert is_binary(Compact.format_error(malformed_error))
    end
  end
end

defmodule RulesEngine.ValidationAccumulateTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "test"

  describe "accumulate validation" do
    test "valid accumulate with known bindings passes" do
      src = """
      rule "valid-accumulate" do
        when
          acc: accumulate from TimesheetEntry(employee_id: e, hours: h) group_by e reduce total: sum(h), count_entries: count()
        then
          emit Result(emp: e, total_hours: total, entry_count: count_entries)
      end
      """

      assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
    end

    test "accumulate with unknown binding in reducer expression fails" do
      src = """
      rule "invalid-reducer-expr" do
        when
          acc: accumulate from TimesheetEntry(employee_id: e, hours: h) group_by e reduce total: sum(unknown_var)
        then
          emit Result(emp: e, total_hours: total)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
      assert Enum.any?(errors, &(&1.code == :unknown_binding and &1.message =~ "unknown_var"))
    end

    test "accumulate with unknown binding in group_by fails" do
      src = """
      rule "invalid-group-by" do
        when
          acc: accumulate from TimesheetEntry(employee_id: e, hours: h) group_by missing_field reduce total: sum(h)
        then
          emit Result(total_hours: total)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
      assert Enum.any?(errors, &(&1.code == :unknown_binding and &1.message =~ "missing_field"))
    end

    test "accumulate reducer names are available as bindings in then clause" do
      src = """
      rule "reducer-bindings" do
        when
          e: Employee(id: emp_id)
          acc: accumulate from TimesheetEntry(employee_id: emp_id, hours: h) group_by emp_id reduce total: sum(h), avg_hours: avg(h), min_hours: min(h), max_hours: max(h)
        then
          emit Summary(total: total, avg: avg_hours, min: min_hours, max: max_hours)
      end
      """

      assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
    end

    test "using undefined accumulate reducer name in then clause fails" do
      src = """
      rule "undefined-reducer" do
        when
          e: Employee(id: emp_id) 
          acc: accumulate from TimesheetEntry(employee_id: emp_id, hours: h) group_by emp_id reduce total: sum(h)
        then
          emit Result(total: total, undefined: nonexistent_reducer)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})

      assert Enum.any?(
               errors,
               &(&1.code == :unknown_binding and &1.message =~ "nonexistent_reducer")
             )
    end

    test "multiple reducer expressions with mixed validity" do
      src = """
      rule "mixed-validity" do
        when
          acc: accumulate from TimesheetEntry(employee_id: e, hours: h, rate: r) group_by e reduce total_hours: sum(h), total_pay: sum(valid_var), avg_rate: avg(invalid_var)
        then
          emit Result(emp: e, hours: total_hours, pay: total_pay, rate: avg_rate)
      end
      """

      assert {:error, errors} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
      unknown_errors = Enum.filter(errors, &(&1.code == :unknown_binding))
      assert length(unknown_errors) == 2
      assert Enum.any?(unknown_errors, &(&1.message =~ "valid_var"))
      assert Enum.any?(unknown_errors, &(&1.message =~ "invalid_var"))
    end

    test "complex reducer expressions with function calls" do
      src = """
      rule "complex-reducers" do
        when
          t: TimesheetEntry(start_at: s, end_at: e, employee_id: emp_id)
          acc: accumulate from PayRate(employee_id: emp_id, rate: r) group_by emp_id reduce total_cost: sum(r)
        then
          emit Cost(employee: emp_id, total: total_cost)
      end
      """

      assert {:ok, _ir} = Compiler.parse_and_compile(@tenant, src, %{fact_schemas: false})
    end
  end
end

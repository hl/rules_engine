defmodule CompilationBench do
  @moduledoc """
  Benchmarks for DSL compilation performance.

  Run with: mix run bench/compilation_bench.exs
  """

  alias RulesEngine.DSL.Parser
  alias RulesEngine.DSL.Compiler
  alias RulesEngine.DSL.Validate
  alias RulesEngine.SchemaRegistry

  @simple_dsl """
  rule "simple-rule" salience: 10 do
    when
      entry: Employee(id: emp_id, hours: h)
      guard h > 40
    then
      emit Overtime(employee_id: emp_id, hours: h - 40)
  end
  """

  @complex_dsl """
  rule "complex-overtime" salience: 50 do
    when
      entry: TimesheetEntry(employee_id: e, hours: h, date: d)
      policy: OvertimePolicy(threshold_hours: t, multiplier: m)
      accumulate sum(hours) from TimesheetEntry(employee_id: e) having total > t
      guard h > t and d >= "2024-01-01"
      not RestrictedDate(date: d)
    then
      emit PayLine(employee_id: e, component: :overtime, hours: h - t, rate: m)
      call log("overtime calculated", %{employee: e, hours: h - t})
  end
  """

  @large_ruleset Enum.map_join(1..100, "\n\n", fn i ->
                   """
                   rule "rule-#{i}" salience: #{i} do
                     when
                       entry: Employee(id: emp_id_#{i}, hours: h_#{i})
                       guard h_#{i} > #{i * 10}
                     then
                       emit Result(id: emp_id_#{i}, value: h_#{i} * #{i})
                   end
                   """
                 end)

  def run do
    # Set up schemas for validation
    SchemaRegistry.clear_schemas()

    schemas = %{
      "Employee" => %{"id" => "string", "hours" => "number"},
      "TimesheetEntry" => %{"employee_id" => "string", "hours" => "number", "date" => "string"},
      "OvertimePolicy" => %{"threshold_hours" => "number", "multiplier" => "number"},
      "RestrictedDate" => %{"date" => "string"},
      "Overtime" => %{"employee_id" => "string", "hours" => "number"},
      "PayLine" => %{
        "employee_id" => "string",
        "component" => "atom",
        "hours" => "number",
        "rate" => "number"
      },
      "Result" => %{"id" => "string", "value" => "number"}
    }

    Enum.each(schemas, fn {name, fields} ->
      SchemaRegistry.register_schema(name, fields)
    end)

    Benchee.run(
      %{
        "parse_simple" => fn -> Parser.parse(@simple_dsl) end,
        "parse_complex" => fn -> Parser.parse(@complex_dsl) end,
        "parse_large_ruleset" => fn -> Parser.parse(@large_ruleset) end,
        "full_compile_simple" => fn ->
          with {:ok, ast} <- Parser.parse(@simple_dsl),
               {:ok, validated_ast} <- Validate.validate_rules(ast, "tenant"),
               {:ok, ir} <- Compiler.compile_to_ir(validated_ast, "tenant") do
            ir
          end
        end,
        "full_compile_complex" => fn ->
          with {:ok, ast} <- Parser.parse(@complex_dsl),
               {:ok, validated_ast} <- Validate.validate_rules(ast, "tenant"),
               {:ok, ir} <- Compiler.compile_to_ir(validated_ast, "tenant") do
            ir
          end
        end,
        "full_compile_large_ruleset" => fn ->
          with {:ok, ast} <- Parser.parse(@large_ruleset),
               {:ok, validated_ast} <- Validate.validate_rules(ast, "tenant"),
               {:ok, ir} <- Compiler.compile_to_ir(validated_ast, "tenant") do
            ir
          end
        end
      },
      memory_time: 2,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.JSON, file: "bench/results/compilation_bench.json"},
        {Benchee.Formatters.HTML, file: "bench/results/compilation_bench.html"}
      ],
      print: [
        benchmarking: true,
        configuration: true,
        fast_warning: true
      ]
    )
  end
end

# Ensure results directory exists
File.mkdir_p!("bench/results")

# Run the benchmark
CompilationBench.run()

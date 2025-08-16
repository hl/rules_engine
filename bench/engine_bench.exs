defmodule EngineBench do
  @moduledoc """
  Benchmarks for engine runtime performance.

  Run with: mix run bench/engine_bench.exs
  """

  alias RulesEngine.Engine
  alias RulesEngine.SchemaRegistry

  @simple_rule """
  rule "overtime-check" salience: 10 do
    when
      entry: Employee(id: emp_id, hours: h)
      guard h > 40
    then
      emit Overtime(employee_id: emp_id, hours: h - 40)
  end
  """

  @complex_rules """
  rule "overtime-check" salience: 50 do
    when
      entry: Employee(id: emp_id, hours: h, department: d)
      policy: OvertimePolicy(department: d, threshold: t, rate: r)
      guard h > t
    then
      emit Overtime(employee_id: emp_id, hours: h - t, rate: r)
  end

  rule "manager-approval" salience: 40 do
    when
      overtime: Overtime(employee_id: e, hours: oh)
      employee: Employee(id: e, manager_id: m)
      guard oh > 10
    then
      emit ApprovalRequired(employee_id: e, manager_id: m, overtime_hours: oh)
  end

  rule "total-calculation" salience: 30 do
    when
      accumulate sum(hours) from Overtime(employee_id: e) having total_hours > 0
    then
      emit WeeklyTotal(employee_id: e, total_overtime: total_hours)
  end
  """

  def setup_engine(rules_dsl) do
    # Set up schemas
    SchemaRegistry.clear_schemas()

    schemas = %{
      "Employee" => %{
        "id" => "string",
        "hours" => "number",
        "department" => "string",
        "manager_id" => "string"
      },
      "OvertimePolicy" => %{"department" => "string", "threshold" => "number", "rate" => "number"},
      "Overtime" => %{"employee_id" => "string", "hours" => "number", "rate" => "number"},
      "ApprovalRequired" => %{
        "employee_id" => "string",
        "manager_id" => "string",
        "overtime_hours" => "number"
      },
      "WeeklyTotal" => %{"employee_id" => "string", "total_overtime" => "number"}
    }

    Enum.each(schemas, fn {name, fields} ->
      SchemaRegistry.register_schema(name, fields)
    end)

    {:ok, engine} = Engine.start_tenant("bench_tenant", rules_dsl)
    engine
  end

  def generate_facts(count) do
    employees =
      Enum.map(1..count, fn i ->
        %{
          "id" => "emp_#{i}",
          "hours" => 35 + :rand.uniform(20),
          "department" => Enum.random(["engineering", "sales", "marketing"]),
          "manager_id" => "mgr_#{rem(i, 10) + 1}"
        }
      end)

    policies = [
      %{"department" => "engineering", "threshold" => 40, "rate" => 1.5},
      %{"department" => "sales", "threshold" => 45, "rate" => 1.3},
      %{"department" => "marketing", "threshold" => 38, "rate" => 1.4}
    ]

    {employees, policies}
  end

  def run do
    # Benchmark fact assertion
    simple_engine = setup_engine(@simple_rule)
    complex_engine = setup_engine(@complex_rules)

    {small_facts, small_policies} = generate_facts(10)
    {medium_facts, medium_policies} = generate_facts(100)
    {large_facts, large_policies} = generate_facts(1000)

    Benchee.run(
      %{
        "assert_10_facts_simple" => fn ->
          Enum.each(small_facts, fn fact ->
            Engine.assert_fact(simple_engine, "Employee", fact)
          end)

          Engine.reset_working_memory(simple_engine)
        end,
        "assert_100_facts_simple" => fn ->
          Enum.each(medium_facts, fn fact ->
            Engine.assert_fact(simple_engine, "Employee", fact)
          end)

          Engine.reset_working_memory(simple_engine)
        end,
        "assert_1000_facts_simple" => fn ->
          Enum.each(large_facts, fn fact ->
            Engine.assert_fact(simple_engine, "Employee", fact)
          end)

          Engine.reset_working_memory(simple_engine)
        end,
        "run_simple_10_facts" => fn ->
          Enum.each(small_facts, fn fact ->
            Engine.assert_fact(simple_engine, "Employee", fact)
          end)

          Engine.run(simple_engine)
          Engine.reset_working_memory(simple_engine)
        end,
        "run_simple_100_facts" => fn ->
          Enum.each(medium_facts, fn fact ->
            Engine.assert_fact(simple_engine, "Employee", fact)
          end)

          Engine.run(simple_engine)
          Engine.reset_working_memory(simple_engine)
        end,
        "run_complex_10_facts" => fn ->
          Enum.each(small_facts, fn fact ->
            Engine.assert_fact(complex_engine, "Employee", fact)
          end)

          Enum.each(small_policies, fn policy ->
            Engine.assert_fact(complex_engine, "OvertimePolicy", policy)
          end)

          Engine.run(complex_engine)
          Engine.reset_working_memory(complex_engine)
        end,
        "run_complex_100_facts" => fn ->
          Enum.each(medium_facts, fn fact ->
            Engine.assert_fact(complex_engine, "Employee", fact)
          end)

          Enum.each(medium_policies, fn policy ->
            Engine.assert_fact(complex_engine, "OvertimePolicy", policy)
          end)

          Engine.run(complex_engine)
          Engine.reset_working_memory(complex_engine)
        end
      },
      memory_time: 2,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.JSON, file: "bench/results/engine_bench.json"},
        {Benchee.Formatters.HTML, file: "bench/results/engine_bench.html"}
      ],
      print: [
        benchmarking: true,
        configuration: true,
        fast_warning: true
      ]
    )

    # Clean up
    Engine.stop_tenant("bench_tenant")
  end
end

# Ensure results directory exists
File.mkdir_p!("bench/results")

# Run the benchmark
EngineBench.run()

src = """
rule "join-test" do
  when
    emp: Employee(id: e)
    ts: TimesheetEntry(employee_id: e)
  then
    emit Out(x: "joined")
end
"""

{:ok, ir} = RulesEngine.DSL.Compiler.parse_and_compile("test", src, %{cache: false})

IO.puts("IR bindings:")
IO.inspect(ir["rules"], pretty: true, limit: :infinity)

IO.puts("\nAlpha network:")
IO.inspect(ir["network"]["alpha"], pretty: true, limit: :infinity)

IO.puts("\nBeta network:")
IO.inspect(ir["network"]["beta"], pretty: true, limit: :infinity)

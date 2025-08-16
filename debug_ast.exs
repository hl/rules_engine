src = """
rule "join-test" do
  when
    emp: Employee(id: e)
    ts: TimesheetEntry(employee_id: e)
  then
    emit Out(x: "joined")
end
"""

{:ok, ast, _} = RulesEngine.DSL.Parser.parse(src)
IO.inspect(ast, pretty: true, limit: :infinity)

# Also inspect the compiled rule
compiled_rule = RulesEngine.DSL.Compiler.compile_rule(hd(ast))
IO.puts("\nCompiled rule:")
IO.inspect(compiled_rule, pretty: true, limit: :infinity)

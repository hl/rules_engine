simple_dsl = "
rule \"test\" do
  when
    entry: Entry(value: 10)
  then
    emit Result(id: \"test\")
end
"

case RulesEngine.DSL.Compiler.parse_and_compile("test_tenant", simple_dsl, %{cache: false}) do
  {:ok, ir} -> IO.puts("Success!")
  {:error, errors} -> IO.inspect(errors, label: "Errors")
end


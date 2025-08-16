
simple_dsl = "
rule \"test_rule\" do
  when
    entry: Entry(value: 10)
    policy: Policy(threshold: 5)  
  then
    emit Result(id: \"test\", score: 42)
end
"

case RulesEngine.DSL.Compiler.parse_and_compile("test_tenant", simple_dsl, %{cache: false}) do
  {:ok, ir} -> 
    IO.puts("✅ Optimization successful!")
    IO.puts("Alpha nodes: #{length(ir["network"]["alpha"])}")
    IO.puts("Beta nodes: #{length(ir["network"]["beta"])}")
  {:error, errors} -> 
    IO.puts("❌ Error: #{inspect(errors)}")
end


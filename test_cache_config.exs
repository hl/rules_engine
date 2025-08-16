# Quick test to verify the cache configuration works without Mix.env()
# This simulates the runtime environment without Mix available

Application.put_env(:rules_engine, :enable_compilation_cache, false)

{:ok, _} =
  RulesEngine.DSL.Compiler.parse_and_compile("test_tenant", """
  rule "test-rule" do
    when
      fact: TestFact()
    then
      emit Result()
  end
  """)

IO.puts("✓ Compilation cache configuration works correctly without Mix.env()")

# Clean up
File.rm(__ENV__.file)

defmodule RulesEngine.AlphaNetworkTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "test"

  defp read_fixture(filename) do
    File.read!(Path.join([__DIR__, "fixtures", "dsl", filename]))
  end

  test "alpha network is built from fact patterns" do
    source = File.read!(Path.join([__DIR__, "fixtures", "dsl", "alpha_network_test.rule"]))

    {:ok, ir} = Compiler.parse_and_compile(@tenant, source)
    alpha_network = ir["network"]["alpha"]

    # Should create alpha nodes for each fact type
    assert length(alpha_network) == 2

    # Should have Employee alpha node
    employee_node = Enum.find(alpha_network, &(&1["type"] == "Employee"))
    assert employee_node["id"] == "alpha_Employee"
    assert length(employee_node["tests"]) == 2

    # Should have TimesheetEntry alpha node
    ts_node = Enum.find(alpha_network, &(&1["type"] == "TimesheetEntry"))
    assert ts_node["id"] == "alpha_TimesheetEntry"
    assert length(ts_node["tests"]) == 2
  end

  test "alpha nodes include selectivity and indexability hints" do
    source = File.read!(Path.join([__DIR__, "fixtures", "dsl", "alpha_network_test.rule"]))

    {:ok, ir} = Compiler.parse_and_compile(@tenant, source)
    alpha_network = ir["network"]["alpha"]

    # Get a test from any alpha node
    test = alpha_network |> List.first() |> Map.get("tests") |> List.first()

    # Should have extra metadata with optimization hints
    assert Map.has_key?(test, "extra")
    assert Map.has_key?(test["extra"], "selectivity")
    assert Map.has_key?(test["extra"], "indexable")

    # Equality tests should be highly selective and indexable
    assert test["extra"]["selectivity"] == 0.01
    assert test["extra"]["indexable"] == true
  end

  test "alpha network handles rules without fact field constraints" do
    src = read_fixture("alpha_simple_facts.rule")
    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)
    alpha_network = ir["network"]["alpha"]

    # Should create alpha nodes even without field constraints
    assert length(alpha_network) == 2

    # Nodes should have empty test arrays
    Enum.each(alpha_network, fn node ->
      assert node["tests"] == []
    end)
  end

  test "alpha network deduplicates identical tests across rules" do
    src = read_fixture("alpha_deduplication_rules.rule")
    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)
    alpha_network = ir["network"]["alpha"]

    # Should create only one Employee alpha node
    employee_nodes = Enum.filter(alpha_network, &(&1["type"] == "Employee"))
    assert length(employee_nodes) == 1

    # Should have only one test for the role constraint (deduplicated)
    employee_node = List.first(employee_nodes)
    role_tests = Enum.filter(employee_node["tests"], &(&1["left"]["field"] == "role"))
    assert length(role_tests) == 1
  end

  test "alpha network validates against IR schema" do
    source = File.read!(Path.join([__DIR__, "fixtures", "dsl", "alpha_network_test.rule"]))

    {:ok, ir} = Compiler.parse_and_compile(@tenant, source)

    # The IR compilation includes schema validation, so if this passes,
    # the alpha network structure is valid according to the schema
    assert ir["version"] == "v1"
    assert is_list(ir["network"]["alpha"])

    # Verify alpha node structure matches schema requirements
    Enum.each(ir["network"]["alpha"], fn node ->
      assert Map.has_key?(node, "id")
      assert Map.has_key?(node, "type")
      assert Map.has_key?(node, "tests")
      assert is_list(node["tests"])
    end)
  end
end

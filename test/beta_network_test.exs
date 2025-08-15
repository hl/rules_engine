defmodule RulesEngine.BetaNetworkTest do
  use ExUnit.Case, async: true

  alias RulesEngine.DSL.Compiler

  @tenant "test"

  test "beta network creates join nodes for multi-fact rules" do
    src = """
    rule "join-test" do
      when
        emp: Employee(id: e)
        ts: TimesheetEntry(employee_id: e)
      then
        emit Out(x: "joined")
    end
    """

    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)
    beta_network = ir["network"]["beta"]

    # Should create one beta join node
    assert length(beta_network) == 1

    beta_node = List.first(beta_network)
    assert beta_node["left"] == "alpha_Employee"
    assert beta_node["right"] == "alpha_TimesheetEntry"
    assert length(beta_node["on"]) == 1

    # Should detect the join condition
    join_condition = List.first(beta_node["on"])
    assert join_condition["op"] == "=="
    assert join_condition["left"]["binding"] == "emp"
    assert join_condition["left"]["field"] == "id"
    assert join_condition["right"]["binding"] == "ts"
    assert join_condition["right"]["field"] == "employee_id"
  end

  test "beta network handles rules with no joins" do
    src = """
    rule "no-join" do
      when
        emp: Employee(id: e)
      then
        emit Out(x: e)
    end
    """

    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)
    beta_network = ir["network"]["beta"]

    # Should create no beta nodes for single-fact rules
    assert Enum.empty?(beta_network)
  end

  test "beta network handles complex multi-way joins" do
    src = """
    rule "three-way-join" do
      when
        emp: Employee(id: e, role: r)
        ts: TimesheetEntry(employee_id: e, hours: h)
        rate: PayRate(employee_id: e)
      then
        emit PayLine(employee_id: e, hours: h, rate: 50)
    end
    """

    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)
    beta_network = ir["network"]["beta"]

    # Should create beta nodes for the join chain
    assert length(beta_network) >= 1

    # All beta nodes should have proper structure
    Enum.each(beta_network, fn node ->
      assert Map.has_key?(node, "id")
      assert Map.has_key?(node, "left")
      assert Map.has_key?(node, "right")
      assert Map.has_key?(node, "on")
      assert is_list(node["on"])
    end)
  end

  test "beta network detects multiple join conditions" do
    src = """
    rule "multi-condition-join" do
      when
        emp: Employee(id: e, location: loc)
        policy: OvertimePolicy(jurisdiction: loc)
        ts: TimesheetEntry(employee_id: e)
      then
        emit Out(x: "complex")
    end
    """

    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)
    beta_network = ir["network"]["beta"]

    # Should create beta nodes with appropriate join conditions
    assert length(beta_network) >= 1

    # Check that join conditions are detected
    total_conditions = Enum.sum(Enum.map(beta_network, fn node -> length(node["on"]) end))
    assert total_conditions >= 1
  end

  test "beta network validates against IR schema" do
    src = """
    rule "schema-test" do
      when
        emp: Employee(id: e)
        ts: TimesheetEntry(employee_id: e)
      then
        emit PayLine(employee_id: e, amount: 100)
    end
    """

    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)

    # The IR compilation includes schema validation, so if this passes,
    # the beta network structure is valid according to the schema
    assert ir["version"] == "v1"
    assert is_list(ir["network"]["beta"])

    # Verify beta node structure matches schema requirements
    Enum.each(ir["network"]["beta"], fn node ->
      assert Map.has_key?(node, "id")
      assert Map.has_key?(node, "left")
      assert Map.has_key?(node, "right")
      assert Map.has_key?(node, "on")
      assert is_list(node["on"])

      # Verify join conditions structure
      Enum.each(node["on"], fn condition ->
        assert Map.has_key?(condition, "left")
        assert Map.has_key?(condition, "op")
        assert Map.has_key?(condition, "right")
        assert condition["op"] == "=="
      end)
    end)
  end

  test "beta network creates unique node IDs" do
    src = """
    rule "unique-ids-1" do
      when
        emp: Employee(id: e)
        ts: TimesheetEntry(employee_id: e)
      then
        emit Out(x: "rule1")
    end

    rule "unique-ids-2" do
      when
        emp2: Employee(id: e2)
        ts2: TimesheetEntry(employee_id: e2)
      then
        emit Out(x: "rule2")
    end
    """

    {:ok, ir} = Compiler.parse_and_compile(@tenant, src)
    beta_network = ir["network"]["beta"]

    # Should create beta nodes with unique IDs
    beta_ids = Enum.map(beta_network, fn node -> node["id"] end)
    assert length(beta_ids) == length(Enum.uniq(beta_ids))
  end
end

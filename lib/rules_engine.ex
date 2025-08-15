defmodule RulesEngine do
  @moduledoc """
  A rules engine for processing business rules using a domain-specific language (DSL).

  This module provides the main public API for parsing rules, compiling them to
  intermediate representation (IR), and working with domain-specific business logic
  for payroll, compliance, and cost estimation use cases.

  ## Usage

      # Parse a rule from DSL text
      rule_text = ~s{
        rule "overtime-check" salience: 50 do
          when
            entry: TimesheetEntry(employee_id: e, hours: h)
            policy: OvertimePolicy(threshold_hours: t, multiplier: m)
            guard h > t
          then
            emit PayLine(employee_id: e, component: :overtime, hours: h - t, rate: m)
        end
      }

      {:ok, ast, warnings} = RulesEngine.parse_rule(rule_text)

      # Compile to IR
      tenant_id = "my-tenant"
      context = %{now: DateTime.utc_now()}
      {:ok, ir} = RulesEngine.compile_rule(tenant_id, rule_text, context)
  """

  alias RulesEngine.DSL.{Compiler, Parser}

  @doc """
  Parse rule DSL text into an Abstract Syntax Tree (AST).

  ## Parameters
  - `rule_text` - String containing DSL rule definition

  ## Returns
  - `{:ok, ast, warnings}` - Successfully parsed AST with any warnings
  - `{:error, errors}` - Parse errors with location information

  ## Examples

      iex> rule = "rule \\"test\\" salience: 10 do\\n  when\\n    fact: Employee(id: x)\\n    guard x > 0\\n  then\\n    emit Result(emp: x)\\nend"
      iex> {:ok, _ast, _warnings} = RulesEngine.parse_rule(rule)
      iex> true
      true
  """
  @spec parse_rule(String.t()) :: {:ok, list(), list()} | {:error, list()}
  def parse_rule(rule_text) when is_binary(rule_text) do
    Parser.parse(rule_text)
  end

  @doc """
  Compile parsed rule DSL into intermediate representation (IR).

  ## Parameters
  - `tenant_id` - Tenant identifier for rule scoping
  - `rule_text` - String containing DSL rule definition
  - `context` - Map containing compilation context (e.g., %{now: DateTime.t()})

  ## Returns
  - `{:ok, ir}` - Successfully compiled intermediate representation
  - `{:error, reason}` - Compilation error

  ## Examples

      iex> rule = "rule \\"test\\" salience: 10 do\\n  when\\n    fact: Employee(id: x)\\n  then\\n    emit Result(emp: x)\\nend"
      iex> context = %{now: DateTime.from_naive!(~N[2025-01-01 00:00:00], "Etc/UTC")}
      iex> {:ok, _ir} = RulesEngine.compile_rule("test-tenant", rule, context)
      iex> true
      true
  """
  @spec compile_rule(String.t(), String.t(), map()) :: {:ok, map()} | {:error, any()}
  def compile_rule(tenant_id, rule_text, context \\ %{})
      when is_binary(tenant_id) and is_binary(rule_text) and is_map(context) do
    Compiler.parse_and_compile(tenant_id, rule_text, context)
  end

  @doc """
  Parse and validate multiple rules from a list of rule texts.

  ## Parameters
  - `rule_texts` - List of strings containing DSL rule definitions

  ## Returns
  - `{:ok, results}` - List of parse results for each rule
  - `{:error, errors}` - Aggregated errors across all rules

  ## Examples

      iex> rules = [
      ...>   ~s{rule "rule1" do\\n  when\\n    fact: Employee(id: 1)\\n  then\\n    emit Result(emp: 2)\\nend},
      ...>   ~s{rule "rule2" do\\n  when\\n    fact: Employee(id: 2)\\n  then\\n    emit Result(emp: 3)\\nend}
      ...> ]
      iex> {:ok, results} = RulesEngine.parse_rules(rules)
      iex> length(results) == 2
      true
  """
  @spec parse_rules([String.t()]) :: {:ok, list()} | {:error, list()}
  def parse_rules(rule_texts) when is_list(rule_texts) do
    results =
      rule_texts
      |> Enum.with_index()
      |> Enum.map(fn {rule_text, index} ->
        case parse_rule(rule_text) do
          {:ok, ast, warnings} -> {:ok, %{index: index, ast: ast, warnings: warnings}}
          {:error, errors} -> {:error, %{index: index, errors: errors}}
        end
      end)

    errors = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {:ok, result} -> result end)}
    else
      {:error, Enum.map(errors, fn {:error, error} -> error end)}
    end
  end

  @doc """
  Get version information for the rules engine.

  ## Returns
  - String version number
  """
  @spec version() :: String.t()
  def version do
    to_string(Application.spec(:rules_engine, :vsn))
  end

  @doc """
  List all supported DSL features and functions.

  ## Returns
  - Map describing available DSL constructs
  """
  @spec dsl_features() :: map()
  def dsl_features do
    %{
      constructs: [
        "rule definitions with salience",
        "when clauses with fact patterns",
        "guard expressions",
        "then clauses with emit statements"
      ],
      functions: [
        "time_between/3 - Calculate time between dates",
        "bucket/2-3 - Group dates into buckets",
        "decimal_add/2, decimal_subtract/2, decimal_multiply/2 - Decimal arithmetic",
        "dec/1 - Create decimal literals"
      ],
      operators: [
        "Comparison: >, <, >=, <=, ==, !=",
        "Boolean: and, or",
        "Set membership: in",
        "Range: between"
      ],
      domains: [
        "payroll - Overtime, rates, premiums",
        "compliance - Regulations, violations",
        "cost_estimation - Labor cost calculations"
      ]
    }
  end
end

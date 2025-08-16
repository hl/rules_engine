defmodule RulesEngineTest.Support.TestCalculators do
  @moduledoc """
  Test calculator functions used in test fixtures.

  This module provides calculator functions referenced by test DSL files
  and fixtures, enabling complete end-to-end testing of the compilation
  pipeline without needing external calculator providers.
  """

  @behaviour RulesEngine.Engine.CalculatorProvider

  @impl true
  def supported_functions do
    [:hours_between, :get_min_wage]
  end

  @impl true
  def evaluate(:hours_between, [start_dt, end_dt]) do
    # Calculate hours between two DateTimes
    diff = DateTime.diff(end_dt, start_dt, :second)
    Decimal.div(Decimal.new(diff), Decimal.new(3600))
  end

  def evaluate(:get_min_wage, [params]) when is_map(params) do
    # Return minimum wage based on jurisdiction parameters
    case params do
      %{"jurisdiction" => "SF"} -> Decimal.new("18.07")
      %{"jurisdiction" => "CA"} -> Decimal.new("16.00")
      %{"jurisdiction" => "US/CA/SF"} -> Decimal.new("18.07")
      _ -> Decimal.new("7.25")
    end
  end

  def evaluate(:get_min_wage, [_params]) do
    # Fallback for non-map parameters
    Decimal.new("15.00")
  end

  @impl true
  def function_info(:hours_between) do
    %{
      arity: 2,
      return_type: :decimal,
      description: "Calculate hours between two DateTimes"
    }
  end

  def function_info(:get_min_wage) do
    %{
      arity: 1,
      return_type: :decimal,
      description: "Get minimum wage from jurisdiction parameters"
    }
  end
end

defmodule RulesEngine.Engine.Activation do
  @moduledoc """
  Activation represents a rule ready to fire.

  An activation is created when a rule's LHS patterns are fully
  satisfied. It contains the production rule, the token with
  bindings, and metadata for agenda ordering.
  """

  alias RulesEngine.Engine.Token

  defstruct [
    # ID of the production rule
    :production_id,
    # Token with complete bindings
    :token,
    # Rule salience for priority
    :salience,
    # Number of patterns in rule
    :specificity,
    # When activation was created
    :inserted_at,
    # Additional rule information
    :rule_metadata
  ]

  @type t :: %__MODULE__{
          production_id: term(),
          token: Token.t(),
          salience: integer(),
          specificity: non_neg_integer(),
          inserted_at: DateTime.t(),
          rule_metadata: map()
        }

  @doc """
  Create new activation for a production rule.
  """
  @spec new(production_id :: term(), token :: Token.t(), opts :: keyword()) :: t()
  def new(production_id, %Token{} = token, opts \\ []) do
    salience = Keyword.get(opts, :salience, 0)
    specificity = Keyword.get(opts, :specificity, length(Token.get_wmes(token)))
    rule_metadata = Keyword.get(opts, :rule_metadata, %{})

    %__MODULE__{
      production_id: production_id,
      token: token,
      salience: salience,
      specificity: specificity,
      inserted_at: DateTime.utc_now(),
      rule_metadata: rule_metadata
    }
  end

  @doc """
  Get the token signature for refraction checking.
  """
  @spec token_signature(t()) :: term()
  def token_signature(%__MODULE__{} = activation) do
    Token.signature(activation.token)
  end

  @doc """
  Get bindings from the activation's token.
  """
  @spec bindings(t()) :: map()
  def bindings(%__MODULE__{} = activation) do
    Token.bindings(activation.token)
  end

  @doc """
  Get WMEs (fact IDs) from the activation's token.
  """
  @spec wmes(t()) :: [term()]
  def wmes(%__MODULE__{} = activation) do
    Token.get_wmes(activation.token)
  end

  @doc """
  Create a unique key for this activation for refraction.
  """
  @spec refraction_key(t()) :: term()
  def refraction_key(%__MODULE__{} = activation) do
    {activation.production_id, token_signature(activation)}
  end

  @doc """
  Get activation age (time since inserted).
  """
  @spec age(t()) :: integer()
  def age(%__MODULE__{} = activation) do
    DateTime.diff(DateTime.utc_now(), activation.inserted_at, :microsecond)
  end
end

defmodule RulesEngine.Engine.PredicateProvider do
  @moduledoc """
  Behaviour for implementing custom predicate providers.

  Host applications can implement this behaviour to add domain-specific
  predicates to the rules engine. Each provider can register multiple
  predicates with evaluation functions, type expectations, and optimisation
  hints.

  ## Example Implementation

      defmodule MyApp.DomainPredicates do
        @behaviour RulesEngine.Engine.PredicateProvider
        
        @supported_ops [:is_valid_email, :within_region, :has_permission]
        
        @impl true
        def supported_ops, do: @supported_ops
        
        @impl true
        def evaluate(:is_valid_email, email, _opts) when is_binary(email) do
          email =~ ~r/^[^@]+@[^@]+\.[^@]+$/
        end
        
        def evaluate(:within_region, location, region) do
          # Custom geo logic
          MyApp.Geo.within?(location, region)
        end
        
        def evaluate(:has_permission, user_id, permission) do
          MyApp.Auth.has_permission?(user_id, permission)
        end
        
        @impl true
        def expectations(:is_valid_email), do: %{string_left?: true}
        def expectations(:within_region), do: %{geo_left?: true, region_right?: true}
        def expectations(:has_permission), do: %{user_id_left?: true, atom_right?: true}
        def expectations(_), do: %{}
        
        @impl true
        def indexable?(:has_permission), do: true  # Can index by user_id
        def indexable?(_), do: false
        
        @impl true
        def selectivity_hint(:is_valid_email), do: 0.1   # Most emails are valid
        def selectivity_hint(:within_region), do: 0.3    # Regional filtering
        def selectivity_hint(:has_permission), do: 0.05  # Highly selective
      end

  Then register during application startup:

      RulesEngine.Engine.PredicateRegistry.register_provider(MyApp.DomainPredicates)
  """

  @doc """
  Return list of predicate operations supported by this provider.

  Must return a list of atoms representing the predicate names.
  Each operation must be implemented in the `evaluate/3` callback.

  ## Examples

      def supported_ops, do: [:is_valid_email, :within_region]
  """
  @callback supported_ops() :: [atom()]

  @doc """
  Evaluate a predicate operation against two values.

  Must return a boolean result. Should raise on invalid arguments
  to catch bugs early in development.

  ## Arguments

  - `operation` - The predicate operation atom
  - `left` - Left operand value  
  - `right` - Right operand value

  ## Examples

      def evaluate(:is_valid_email, email, _opts) when is_binary(email) do
        email =~ ~r/^[^@]+@[^@]+\.[^@]+$/
      end
  """
  @callback evaluate(operation :: atom(), left :: term(), right :: term()) :: boolean()

  @doc """
  Return type expectations and validation requirements for predicates.

  Used during AST validation to catch type mismatches early.
  Returns a map with constraint flags that will be checked during compilation.

  ## Common Constraint Flags

  - `string_left?: true` - Left operand must be a string
  - `string_right?: true` - Right operand must be a string
  - `numeric_left?: true` - Left operand must be numeric
  - `numeric_right?: true` - Right operand must be numeric
  - `collection_left?: true` - Left operand must be a collection
  - `datetime_required?: true` - Both operands must be DateTime structs
  - `regex_right?: true` - Right operand must be a regex pattern

  ## Examples

      def expectations(:is_valid_email), do: %{string_left?: true}
      def expectations(:within_region), do: %{geo_left?: true, region_right?: true}
      def expectations(_), do: %{}  # No constraints for unknown operations
  """
  @callback expectations(operation :: atom()) :: map()

  @doc """
  Check if a predicate is indexable at alpha or join nodes.

  Returns true for predicates that support efficient indexing in the RETE network.
  Indexable predicates can be used for fast fact lookup and join optimisation.

  Generally, equality-like operations (==, in, has_key) are indexable,
  while fuzzy operations (contains, matches, approximately) are not.

  ## Examples

      def indexable?(:user_has_role), do: true   # Can index by user_id
      def indexable?(:email_contains), do: false # Cannot efficiently index substring searches
  """
  @callback indexable?(operation :: atom()) :: boolean()

  @doc """
  Get selectivity hint for query optimisation.

  Returns a float in [0.0, 1.0] where lower values indicate more selective predicates.
  The query optimiser uses these hints to order predicate evaluation for best performance.

  ## Guidelines

  - `0.01-0.05` - Highly selective (exact matches, unique keys)
  - `0.1-0.3` - Moderately selective (filtered lists, categorisation)
  - `0.3-0.7` - Broad matches (fuzzy searches, ranges)
  - `0.7-0.9` - Mostly inclusive (validation checks that usually pass)

  ## Examples

      def selectivity_hint(:exact_match), do: 0.01      # Very selective
      def selectivity_hint(:within_category), do: 0.2   # Moderately selective
      def selectivity_hint(:is_valid), do: 0.8          # Usually true
  """
  @callback selectivity_hint(operation :: atom()) :: float()

  @optional_callbacks [expectations: 1, indexable?: 1, selectivity_hint: 1]
end

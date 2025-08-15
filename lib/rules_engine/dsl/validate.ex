defmodule RulesEngine.DSL.Validate do
  @moduledoc """
  Compile-time validation for DSL AST before IR generation.
  Ensures supported ops and basic operand shapes; checks binding references exist.
  """

  alias RulesEngine.Predicates

  @type error :: %{code: atom(), message: String.t(), path: term()}

  @spec validate(list(), map()) :: {:ok, list()} | {:error, [error()]}
  def validate(ast, opts) when is_list(ast) do
    schemas =
      case Map.get(opts, :fact_schemas) do
        nil ->
          # Use canonical schemas by default
          RulesEngine.FactSchemas.canonical_schemas()

        custom_schemas when is_map(custom_schemas) ->
          # Merge custom schemas with canonical ones (custom takes precedence)
          Map.merge(RulesEngine.FactSchemas.canonical_schemas(), custom_schemas)

        false ->
          # Explicitly disable schema validation
          nil
      end

    errors =
      Enum.flat_map(ast, &validate_rule(&1, schemas))

    if errors == [], do: {:ok, ast}, else: {:error, errors}
  end

  defp validate_rule(%{name: name, when: {:when, whens}, then: {:then, thens}}, schemas),
    do: validate_rule_core(name, whens, thens, schemas)

  defp validate_rule_core(name, whens, thens, schemas) do
    thens =
      case thens do
        {:then, list} -> list
        list -> list
      end

    bindings = collect_bindings(whens)

    type_field_errors =
      Enum.flat_map(whens, &validate_type_fields(&1, schemas, [name, :when]))

    guard_errors =
      Enum.flat_map(whens, fn
        {:guard, expr} ->
          validate_guard(expr, bindings, [name, :guard])

        {:fact, _b, _t, fields} ->
          Enum.flat_map(fields, &validate_field_constraint(&1, bindings, name))

        {:exists, {:fact, binding, type, fields}} ->
          validate_type_fields({:fact, binding, type, fields}, schemas, [name, :exists])

        {:not, {:exists, {:fact, binding, type, fields}}} ->
          validate_type_fields({:fact, binding, type, fields}, schemas, [name, :not, :exists])

        {:not, {:fact, binding, type, fields}} ->
          validate_type_fields({:fact, binding, type, fields}, schemas, [name, :not])

        {:accumulate, _binding, from_fact, group_by, reducers, having} ->
          validate_accumulate(from_fact, group_by, reducers, having, bindings, [name, :accumulate])

        _ ->
          []
      end)

    action_errors =
      thens
      |> List.wrap()
      |> Enum.flat_map(&validate_action(&1, bindings, schemas, [name, :then]))
      |> Enum.reject(&is_nil/1)

    type_field_errors ++ guard_errors ++ action_errors
  end

  defp collect_bindings(whens) do
    whens
    |> Enum.flat_map(fn
      {:fact, binding, _type, fields} ->
        refs = Enum.flat_map(fields, &extract_field_binding_refs/1)
        Enum.reject([binding | refs], &is_nil/1)

      {:exists, {:fact, binding, _t, fields}} ->
        refs = Enum.flat_map(fields, &extract_field_binding_refs/1)
        Enum.reject([binding | refs], &is_nil/1)

      {:not, {:fact, binding, _t, fields}} ->
        refs = Enum.flat_map(fields, &extract_field_binding_refs/1)
        Enum.reject([binding | refs], &is_nil/1)

      {:not, {:exists, {:fact, binding, _t, fields}}} ->
        refs = Enum.flat_map(fields, &extract_field_binding_refs/1)
        Enum.reject([binding | refs], &is_nil/1)

      {:accumulate, binding, from_fact, _gb, reducers, _having} ->
        from_bindings = extract_fact_bindings(from_fact)
        acc_names = Enum.flat_map(reducers, &extract_accumulate_name/1)
        Enum.reject([binding] ++ from_bindings ++ acc_names, &is_nil/1)

      _ ->
        []
    end)
    |> MapSet.new()
  end

  defp validate_action({:emit, type, fields}, bindings, schemas, path) do
    field_errors =
      fields
      |> Enum.flat_map(fn {_k, v} -> validate_term(v, bindings, path ++ [:action]) end)

    # Also validate emit field names against schema if available
    emit_schema_errors = validate_emit_fields(type, fields, schemas, path ++ [:emit])

    field_errors ++ emit_schema_errors
  end

  defp validate_action({:call, _mod, _fun, args}, bindings, _schemas, path) do
    # Validate all arguments use valid bindings
    args
    |> Enum.flat_map(fn arg -> validate_term(arg, bindings, path ++ [:call]) end)
  end

  defp validate_action({:log, _level, message}, bindings, _schemas, path) do
    # Validate log message uses valid bindings
    validate_term(message, bindings, path ++ [:log])
  end

  # validate_guard grouped clauses (all heads contiguous)
  defp validate_guard({:between, v, l, r}, bindings, path),
    do: validate_between({:between, v, l, r}, bindings, path)

  defp validate_guard(list, bindings, path) when is_list(list),
    do: Enum.flat_map(list, &validate_guard(&1, bindings, path))

  defp validate_guard({:and, a, b}, bindings, path),
    do: validate_guard(a, bindings, path) ++ validate_guard(b, bindings, path)

  defp validate_guard({:or, a, b}, bindings, path),
    do: validate_guard(a, bindings, path) ++ validate_guard(b, bindings, path)

  defp validate_guard({:set, op, binding_or_value, list}, bindings, path) do
    op_atom = normalize_op(op)

    errs =
      if op_atom in Predicates.supported_ops(),
        do: [],
        else: [
          %{code: :unsupported_op, message: "unsupported op #{inspect(op)}", path: path}
        ]

    # Validate binding references in the set operation
    set_errors = validate_term(binding_or_value, bindings, path)
    list_errors = Enum.flat_map(list, &validate_term(&1, bindings, path))

    errs ++ set_errors ++ list_errors
  end

  defp validate_guard({:cmp, op, l, r}, bindings, path) do
    op_atom = normalize_op(op)

    errs = []

    # Check if operation is supported
    errs =
      if op_atom in Predicates.supported_ops(),
        do: errs,
        else: [
          %{code: :unsupported_op, message: "unsupported op #{inspect(op)}", path: path} | errs
        ]

    # Apply predicate-specific type expectations
    expectations = Predicates.expectations(op_atom)
    type_errors = validate_predicate_expectations(op_atom, l, r, expectations, path)

    errs ++ type_errors ++ validate_term(l, bindings, path) ++ validate_term(r, bindings, path)
  end

  defp collection_like?({:call, _name, _args}), do: true
  defp collection_like?(%{"type" => "list"}), do: true
  defp collection_like?(_), do: false

  # grouped validate_guard/3 helper
  defp validate_between({:between, v, l, r}, bindings, path) do
    errs =
      if comparable_literal?(l) and comparable_literal?(r) do
        []
      else
        [
          %{
            code: :invalid_operand,
            message: "between bounds must be comparable literals",
            path: path
          }
        ]
      end

    errs ++
      validate_term(v, bindings, path) ++
      validate_term(l, bindings, path) ++ validate_term(r, bindings, path)
  end

  defp validate_type_fields(_node, nil, _path), do: []

  defp validate_type_fields({:fact, _b, type, fields}, schemas, path) do
    case Map.get(schemas || %{}, type) do
      nil ->
        []

      %{"fields" => allowed} ->
        Enum.flat_map(fields, &validate_field_allowed(&1, allowed, type, path))
    end
  end

  defp validate_type_fields(_other, _schemas, _path), do: []

  defp validate_field_allowed({k, _v}, allowed, type, path) do
    if to_string(k) in allowed do
      []
    else
      [
        %{
          code: :unknown_field,
          message: "unknown field #{k} for #{type}",
          path: path ++ [type, k]
        }
      ]
    end
  end

  defp validate_field_constraint({_k, v}, bindings, name) do
    case v do
      {:cmp, op, l, r} -> validate_guard({:cmp, op, l, r}, bindings, [name, :alpha])
      {:set, _kind, _name, _list} -> []
      _ -> []
    end
  end

  defp extract_accumulate_name({name, _reducer_spec}) when is_binary(name), do: [name]
  defp extract_accumulate_name(_), do: []

  defp extract_field_binding_refs({_k, v}) do
    case v do
      [binding_ref: n] -> [n]
      {:cmp, _op, {:binding_ref, n}, _} -> [n]
      {:cmp, _op, _, {:binding_ref, n}} -> [n]
      _ -> []
    end
  end

  defp validate_term({:binding_ref, name}, bindings, path) do
    if MapSet.member?(bindings, name) or name in ["_b0", "_b1", "_b2", "_b3"] do
      []
    else
      [%{code: :unknown_binding, message: "unknown binding #{inspect(name)}", path: path}]
    end
  end

  defp validate_term({:call, _name, args}, bindings, path),
    do: Enum.flat_map(args, &validate_term(&1, bindings, path))

  defp validate_term({:arith, _op, l, r}, bindings, path),
    do: validate_term(l, bindings, path) ++ validate_term(r, bindings, path)

  defp validate_term([binding_ref: name], bindings, path) do
    if MapSet.member?(bindings, name) or name in ["_b0", "_b1", "_b2", "_b3"] do
      []
    else
      [%{code: :unknown_binding, message: "unknown binding #{inspect(name)}", path: path}]
    end
  end

  defp validate_term(_other, _bindings, _path), do: []

  # Validate accumulate expressions: from_fact, group_by, reducers, having
  defp validate_accumulate(from_fact, group_by, reducers, having, bindings, path) do
    from_errors = validate_accumulate_from_fact(from_fact, path ++ [:from])
    group_by_errors = validate_term(group_by, bindings, path ++ [:group_by])

    reducer_errors =
      Enum.flat_map(reducers, fn {_name, reducer} ->
        validate_reducer_expression(reducer, bindings, path ++ [:reduce])
      end)

    having_errors =
      case having do
        nil -> []
        having_expr -> validate_guard(having_expr, bindings, path ++ [:having])
      end

    from_errors ++ group_by_errors ++ reducer_errors ++ having_errors
  end

  # Validate reducer expressions like {:sum, expr}, {:count, nil}, etc.
  defp validate_reducer_expression({:sum, expr}, bindings, path),
    do: validate_term(expr, bindings, path)

  defp validate_reducer_expression({:min, expr}, bindings, path),
    do: validate_term(expr, bindings, path)

  defp validate_reducer_expression({:max, expr}, bindings, path),
    do: validate_term(expr, bindings, path)

  defp validate_reducer_expression({:avg, expr}, bindings, path),
    do: validate_term(expr, bindings, path)

  defp validate_reducer_expression({:count, nil}, _bindings, _path), do: []

  defp validate_reducer_expression(_other, _bindings, _path), do: []

  # Validate emit action field names against schema
  defp validate_emit_fields(type, fields, schemas, path) do
    # If schemas are disabled (nil), skip validation
    if schemas == nil do
      []
    else
      case Map.get(schemas, type) do
        nil ->
          # No schema available for this type, skip validation
          []

        %{"fields" => allowed_fields} ->
          Enum.flat_map(fields, fn {field_name, _value} ->
            field_str = to_string(field_name)

            if field_str in allowed_fields do
              []
            else
              [
                %{
                  code: :unknown_field,
                  message: "unknown field #{field_name} for #{type} in emit action",
                  path: path ++ [type, field_name]
                }
              ]
            end
          end)
      end
    end
  end

  # Validate the from fact in accumulate statements
  defp validate_accumulate_from_fact({:fact, _type, _field_binding, fields}, _path) do
    # This validates the fact pattern structure, field validation is handled elsewhere
    # For now, just validate any embedded constraints
    Enum.flat_map(fields, fn
      {_k, {:cmp, _op, _l, _r}} ->
        # Field constraints are validated elsewhere, this is a placeholder
        []

      _ ->
        []
    end)
  end

  defp validate_accumulate_from_fact(_other, _path), do: []

  # Validate predicate type expectations using Predicates.expectations/1
  defp validate_predicate_expectations(op, left, right, expectations, path) do
    errors = []

    errors =
      if Map.get(expectations, :datetime_required?, false) do
        if datetime_like?(left) or datetime_like?(right) do
          errors
        else
          [
            %{
              code: :invalid_operand,
              message: "#{op} requires at least one datetime/date operand",
              path: path
            }
            | errors
          ]
        end
      else
        errors
      end

    errors =
      if Map.get(expectations, :collection_left?, false) do
        if collection_like?(left) do
          errors
        else
          [
            %{
              code: :invalid_operand,
              message: "#{op} requires collection left operand",
              path: path
            }
            | errors
          ]
        end
      else
        errors
      end

    errors =
      if Map.get(expectations, :numeric_right?, false) do
        if number_literal?(right) do
          errors
        else
          [
            %{
              code: :invalid_operand,
              message: "#{op} requires numeric right operand",
              path: path
            }
            | errors
          ]
        end
      else
        errors
      end

    errors
  end

  # Extract bindings from a fact pattern for use in accumulate
  defp extract_fact_bindings({:fact, _type, {_field, [binding_ref: binding]}, fields}) do
    field_bindings = Enum.flat_map(fields, &extract_field_binding_refs/1)
    [binding] ++ field_bindings
  end

  defp extract_fact_bindings(_other), do: []

  defp normalize_op(op) when is_binary(op), do: String.to_atom(op)
  defp normalize_op(op) when is_atom(op), do: op

  defp datetime_like?({:datetime, _}), do: true
  defp datetime_like?({:date, _}), do: true
  defp datetime_like?(%{"type" => t}) when t in ["datetime", "date"], do: true
  defp datetime_like?(_), do: false

  defp number_literal?(%Decimal{}), do: true
  defp number_literal?(i) when is_integer(i), do: true
  defp number_literal?(%{"type" => "number"}), do: true
  defp number_literal?(_), do: false

  defp comparable_literal?({:date, _}), do: true
  defp comparable_literal?({:datetime, _}), do: true
  defp comparable_literal?(i) when is_integer(i), do: true
  defp comparable_literal?(%Decimal{}), do: true

  defp comparable_literal?(%{"type" => t}) when t in ["number", "decimal", "date", "datetime"],
    do: true

  defp comparable_literal?(_), do: false
end

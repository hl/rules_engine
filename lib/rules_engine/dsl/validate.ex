defmodule RulesEngine.DSL.Validate do
  @moduledoc """
  Compile-time validation for DSL AST before IR generation.
  Ensures supported ops and basic operand shapes; checks binding references exist.
  """

  alias RulesEngine.Predicates

  @type error :: %{code: atom(), message: String.t(), path: term()}

  @spec validate(list(), map()) :: {:ok, list()} | {:error, [error()]}
  def validate(ast, opts) when is_list(ast) do
    schemas = Map.get(opts, :fact_schemas)

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

        {:exists, {:fact, _b, _t, _fields}} ->
          []

        {:not, {:exists, {:fact, _b, _t, _fields}}} ->
          []

        {:not, {:fact, _b, _t, _fields}} ->
          []

        _ ->
          []
      end)

    action_errors =
      thens
      |> List.wrap()
      |> Enum.flat_map(&validate_action(&1, bindings, [name, :then]))
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

      {:accumulate, binding, _from, _gb, reducers, _having} ->
        acc_names = Enum.flat_map(reducers, &extract_accumulate_name/1)
        Enum.reject([binding | acc_names], &is_nil/1)

      _ ->
        []
    end)
    |> MapSet.new()
  end

  defp validate_action({:emit, _type, fields}, bindings, path) do
    fields
    |> Enum.flat_map(fn {_k, v} -> validate_term(v, bindings, path ++ [:action]) end)
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

  defp validate_guard({:cmp, op, l, r}, bindings, path) do
    op_atom = normalize_op(op)

    errs = []

    errs =
      if op_atom in Predicates.supported_ops(),
        do: errs,
        else: [
          %{code: :unsupported_op, message: "unsupported op #{inspect(op)}", path: path} | errs
        ]

    errs =
      if op_atom in [:before, :after] and not (datetime_like?(r) or datetime_like?(l)) do
        [
          %{
            code: :invalid_operand,
            message: "before/after require a datetime/date operand",
            path: path
          }
          | errs
        ]
      else
        errs
      end

    errs =
      if op_atom in [:size_eq, :size_gt] and not number_literal?(r) do
        [
          %{code: :invalid_operand, message: "size_* requires numeric right operand", path: path}
          | errs
        ]
      else
        errs
      end

    errs =
      if op_atom in [:size_eq, :size_gt] and not collection_like?(l) do
        [
          %{
            code: :invalid_operand,
            message: "size_* requires collection left operand",
            path: path
          }
          | errs
        ]
      else
        errs
      end

    errs ++ validate_term(l, bindings, path) ++ validate_term(r, bindings, path)
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

    errs ++ validate_term(v, bindings, path)
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

  defp extract_accumulate_name({:sum, _expr}), do: []
  defp extract_accumulate_name({:count, nil}), do: []
  defp extract_accumulate_name({name, _}) when is_binary(name), do: [name]
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

  defp validate_term(_other, _bindings, _path), do: []

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

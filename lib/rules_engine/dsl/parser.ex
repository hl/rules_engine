defmodule RulesEngine.DSL.Parser do
  @moduledoc """
  DSL parser producing an AST per specs/parser_contract.md and EBNF in specs/dsl_ebnf.md.
  """
  import NimbleParsec

  @type ast :: list()

  # Basic lexemes
  whitespace = ascii_string([?\t, ?\f, ?\r, ?\n, ?\v, 32], min: 1)
  newline = choice([string("\r\n"), string("\n")])

  ident_start = ascii_string([?A..?Z, ?a..?z], 1)
  ident_rest = ascii_string([?A..?Z, ?a..?z, ?0..?9, ?_], min: 0)

  ident =
    concat(ident_start, ident_rest)
    |> reduce({List, :to_string, []})
    |> label("identifier")

  # string literal
  escaped_quote = string("\\\"")
  string_char = lookahead_not(string("\"")) |> utf8_char([])
  string_inner = repeat(choice([escaped_quote, string_char]))

  string_lit =
    ignore(string("\""))
    |> concat(string_inner)
    |> ignore(string("\""))
    |> reduce({__MODULE__, :reduce_string, []})

  bool_lit =
    choice([
      string("true") |> replace(true),
      string("false") |> replace(false)
    ])

  # number (integer or decimal)
  sign = optional(string("-"))
  digits = ascii_string([?0..?9], min: 1)

  number_lit =
    sign
    |> concat(digits)
    |> optional(ignore(string(".")) |> concat(digits))
    |> reduce({__MODULE__, :reduce_number, []})

  # date and datetime literals
  date_lit =
    ignore(string("D'"))
    |> concat(ascii_string([?0..?9, ?-], 10))
    |> ignore(string("'"))
    |> reduce({__MODULE__, :reduce_date, []})

  datetime_lit =
    ignore(string("DT'"))
    |> concat(ascii_string([?0..?9, ?-, ?T, ?:, ?Z], min: 20))
    |> ignore(string("'"))
    |> reduce({__MODULE__, :reduce_datetime, []})

  # atoms like :daily, :overtime
  atom_lit = ignore(string(":")) |> concat(ident) |> reduce({__MODULE__, :reduce_atom, []})

  literal = choice([string_lit, bool_lit, number_lit, date_lit, datetime_lit, atom_lit])

  # Forward declarations
  defcombinatorp(:ident, ident)
  defcombinatorp(:literal, literal)

  defcombinatorp(:ws, ignore(optional(whitespace)))
  defcombinatorp(:comma, parsec(:ws) |> ignore(string(",")) |> parsec(:ws))
  defcombinatorp(:colon, parsec(:ws) |> ignore(string(":")) |> parsec(:ws))
  defcombinatorp(:lparen, parsec(:ws) |> ignore(string("(")) |> parsec(:ws))
  defcombinatorp(:rparen, parsec(:ws) |> ignore(string(")")) |> parsec(:ws))
  defcombinatorp(:lbrack, parsec(:ws) |> ignore(string("[")) |> parsec(:ws))
  defcombinatorp(:rbrack, parsec(:ws) |> ignore(string("]")) |> parsec(:ws))

  # value_expr
  defcombinatorp(
    :value_expr,
    choice([
      parsec(:literal),
      parsec(:function_call),
      parsec(:arithmetic),
      parsec(:binding_ref)
    ])
  )

  defcombinatorp(:binding_ref, parsec(:ident) |> unwrap_and_tag(:binding_ref))

  # function_call: ident '(' [args] ')'
  defcombinatorp(
    :function_call,
    parsec(:ident)
    |> ignore(parsec(:lparen))
    |> optional(parsec(:arg_list))
    |> ignore(parsec(:rparen))
    |> reduce({__MODULE__, :reduce_fun_call, []})
  )

  defcombinatorp(
    :arg_list,
    parsec(:value_expr)
    |> repeat(ignore(parsec(:comma)) |> concat(parsec(:value_expr)))
    |> tag(:args)
  )

  # arithmetic: left-associative minimal + - * /
  arith_op = choice([string("+"), string("-"), string("*"), string("/")])

  defcombinatorp(
    :arithmetic,
    choice([
      parsec(:literal),
      parsec(:binding_ref),
      parsec(:function_call)
    ])
    |> ignore(parsec(:ws))
    |> concat(arith_op)
    |> ignore(parsec(:ws))
    |> concat(
      choice([
        parsec(:literal),
        parsec(:binding_ref),
        parsec(:function_call)
      ])
    )
    |> reduce({__MODULE__, :reduce_arith, []})
  )

  # comparison and set and between
  comp_op =
    choice([string("=="), string("!="), string(">="), string("<="), string(">"), string("<")])

  defcombinatorp(
    :comparison_expr,
    parsec(:value_expr)
    |> ignore(parsec(:ws))
    |> concat(comp_op)
    |> ignore(parsec(:ws))
    |> concat(parsec(:value_expr))
    |> reduce({__MODULE__, :reduce_comp, []})
  )

  defcombinatorp(
    :set_expr,
    parsec(:binding_ref)
    |> ignore(parsec(:ws))
    |> choice([
      string("in") |> replace(:in),
      string("not_in") |> replace(:not_in)
    ])
    |> ignore(parsec(:ws))
    |> ignore(parsec(:lbrack))
    |> concat(
      optional(
        parsec(:value_expr)
        |> repeat(ignore(parsec(:comma)) |> concat(parsec(:value_expr)))
      )
    )
    |> ignore(parsec(:rbrack))
    |> reduce({__MODULE__, :reduce_set, []})
  )

  defcombinatorp(
    :between_expr,
    parsec(:value_expr)
    |> ignore(parsec(:ws))
    |> ignore(string("between"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:value_expr))
    |> ignore(parsec(:ws))
    |> ignore(string("and"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:value_expr))
    |> reduce({__MODULE__, :reduce_between, []})
  )

  defcombinatorp(
    :guard_term,
    choice([
      ignore(string("(")) |> concat(parsec(:guard_expr)) |> ignore(string(")")),
      parsec(:comparison_expr),
      parsec(:set_expr),
      parsec(:between_expr)
    ])
  )

  defcombinatorp(
    :guard_expr,
    parsec(:guard_term)
    |> repeat(
      ignore(parsec(:ws))
      |> choice([string("and") |> replace(:and), string("or") |> replace(:or)])
      |> ignore(parsec(:ws))
      |> concat(parsec(:guard_term))
    )
    |> reduce({__MODULE__, :reduce_logical, []})
  )

  # field_match: ident ':' match_expr
  defcombinatorp(
    :field_match,
    parsec(:ident)
    |> ignore(parsec(:colon))
    |> concat(parsec(:match_expr))
    |> reduce({__MODULE__, :reduce_field_match, []})
  )

  defcombinatorp(
    :match_expr,
    choice([
      parsec(:literal),
      parsec(:binding_ref),
      string("_") |> replace(:_),
      parsec(:comparison_expr),
      parsec(:set_expr)
    ])
    |> tag(:match_expr)
  )

  # fact_pattern: [binding ':'] type '(' field_match { ',' field_match } ')'
  defcombinatorp(
    :fact_pattern,
    optional(parsec(:ident) |> ignore(parsec(:colon)))
    |> concat(parsec(:ident))
    |> ignore(parsec(:lparen))
    |> concat(
      optional(
        parsec(:field_match)
        |> repeat(ignore(parsec(:comma)) |> concat(parsec(:field_match)))
      )
    )
    |> ignore(parsec(:rparen))
    |> reduce({__MODULE__, :reduce_fact_pattern, []})
    |> ignore(optional(parsec(:ws)))
  )

  # guard stmt
  defcombinatorp(
    :guard_stmt,
    ignore(string("guard")) |> ignore(parsec(:ws)) |> concat(parsec(:guard_expr)) |> tag(:guard)
  )

  # action: emit Type '(' field_assign {,} ')'
  defcombinatorp(
    :field_assign,
    parsec(:ident)
    |> ignore(parsec(:colon))
    |> concat(parsec(:value_expr))
    |> reduce({__MODULE__, :reduce_field_assign, []})
  )

  defcombinatorp(
    :action_stmt,
    ignore(string("emit"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:ident))
    |> ignore(parsec(:lparen))
    |> concat(
      optional(
        parsec(:field_assign)
        |> repeat(ignore(parsec(:comma)) |> concat(parsec(:field_assign)))
      )
    )
    |> ignore(parsec(:rparen))
    |> reduce({__MODULE__, :reduce_action, []})
  )

  # exists/not statements
  defcombinatorp(
    :exists_stmt,
    ignore(string("exists"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:fact_pattern))
    |> reduce({__MODULE__, :reduce_exists, []})
  )

  defcombinatorp(
    :not_exists_stmt,
    ignore(string("not"))
    |> ignore(parsec(:ws))
    |> ignore(string("exists"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:fact_pattern))
    |> reduce({__MODULE__, :reduce_not_exists, []})
  )

  defcombinatorp(
    :not_fact_stmt,
    ignore(string("not"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:fact_pattern))
    |> reduce({__MODULE__, :reduce_not_fact, []})
  )

  # when_block lines
  defcombinatorp(
    :when_line,
    ignore(optional(parsec(:ws)))
    |> concat(
      choice([
        parsec(:guard_stmt),
        parsec(:exists_stmt),
        parsec(:not_exists_stmt),
        parsec(:not_fact_stmt),
        parsec(:accumulate_stmt),
        parsec(:fact_pattern)
      ])
    )
    |> ignore(optional(parsec(:ws)))
  )

  defcombinatorp(
    :when_block,
    parsec(:when_line)
    |> ignore(optional(newline))
    |> repeat(parsec(:when_line) |> ignore(optional(newline)))
    |> ignore(optional(parsec(:ws)))
    |> tag(:when)
  )

  # accumulate statement
  defcombinatorp(
    :accumulate_stmt,
    optional(parsec(:ident) |> ignore(parsec(:colon)))
    |> ignore(string("accumulate"))
    |> ignore(parsec(:ws))
    |> ignore(string("from"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:fact_pattern))
    |> ignore(parsec(:ws))
    |> ignore(string("group_by"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:group_list))
    |> ignore(parsec(:ws))
    |> ignore(string("reduce"))
    |> ignore(parsec(:ws))
    |> concat(parsec(:reduce_list))
    |> optional(
      ignore(parsec(:ws))
      |> ignore(string("having"))
      |> ignore(parsec(:ws))
      |> concat(parsec(:guard_expr))
      |> tag(:having)
    )
    |> reduce({__MODULE__, :reduce_accumulate, []})
  )

  defcombinatorp(
    :group_list,
    parsec(:value_expr)
    |> repeat(ignore(parsec(:comma)) |> concat(parsec(:value_expr)))
    |> tag(:group_by)
  )

  defcombinatorp(
    :reduce_list,
    parsec(:reduce_item)
    |> repeat(ignore(parsec(:comma)) |> concat(parsec(:reduce_item)))
    |> tag(:reducers)
  )

  defcombinatorp(
    :reduce_item,
    parsec(:ident)
    |> ignore(parsec(:colon))
    |> concat(parsec(:reducer_call))
    |> reduce({__MODULE__, :reduce_named_reducer, []})
  )

  defcombinatorp(
    :reducer_call,
    choice([
      ignore(string("sum"))
      |> ignore(parsec(:lparen))
      |> concat(parsec(:value_expr))
      |> ignore(parsec(:rparen))
      |> tag(:sum),
      ignore(string("count"))
      |> ignore(parsec(:lparen))
      |> ignore(parsec(:rparen))
      |> tag(:count),
      ignore(string("min"))
      |> ignore(parsec(:lparen))
      |> concat(parsec(:value_expr))
      |> ignore(parsec(:rparen))
      |> tag(:min),
      ignore(string("max"))
      |> ignore(parsec(:lparen))
      |> concat(parsec(:value_expr))
      |> ignore(parsec(:rparen))
      |> tag(:max),
      ignore(string("avg"))
      |> ignore(parsec(:lparen))
      |> concat(parsec(:value_expr))
      |> ignore(parsec(:rparen))
      |> tag(:avg)
    ])
  )

  # then_block lines
  defcombinatorp(
    :then_block,
    repeat(ignore(optional(parsec(:ws))) |> concat(parsec(:action_stmt)) |> ignore(newline))
    |> optional(
      ignore(optional(parsec(:ws)))
      |> concat(parsec(:action_stmt))
      |> ignore(optional(newline))
    )
    |> tag(:then)
  )

  # rule
  defcombinatorp(
    :rule,
    ignore(string("rule"))
    |> ignore(parsec(:ws))
    |> concat(string_lit)
    |> optional(
      ignore(parsec(:ws))
      |> ignore(string("salience"))
      |> ignore(parsec(:colon))
      |> concat(number_lit)
    )
    |> ignore(parsec(:ws))
    |> ignore(string("do"))
    |> ignore(parsec(:ws))
    |> ignore(string("when"))
    |> ignore(newline)
    |> concat(parsec(:when_block))
    |> ignore(optional(newline))
    |> ignore(string("then"))
    |> ignore(newline)
    |> concat(parsec(:then_block))
    |> ignore(optional(newline))
    |> ignore(string("end"))
    |> ignore(optional(newline))
    |> reduce({__MODULE__, :reduce_rule, []})
  )

  defcombinatorp(
    :program,
    ignore(optional(parsec(:ws)))
    |> concat(parsec(:rule))
    |> repeat(ignore(optional(parsec(:ws))) |> concat(parsec(:rule)))
    |> ignore(optional(parsec(:ws)))
  )

  defparsec(:do_parse, parsec(:program))

  @spec parse(String.t()) :: {:ok, list(), list()} | {:error, list()}
  def parse(source) when is_binary(source) do
    case __MODULE__.do_parse(source) do
      {:ok, result, _, _, _, _} ->
        {:ok, result, []}

      {:error, reason, _rest, _ctx, _loc, byte_offset} ->
        {line, col} = byte_offset_to_line_col(source, byte_offset)
        {snippet, caret} = build_snippet(source, line, col)

        {:error,
         [
           %{
             code: :parse_error,
             message: to_string(reason),
             line: line,
             column: col,
             snippet: snippet,
             caret: caret
           }
         ]}
    end
  end

  @doc false
  @spec byte_offset_to_line_col(String.t(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  defp byte_offset_to_line_col(src, offset) do
    {line, col, _acc} =
      src
      |> String.graphemes()
      |> Enum.reduce_while({1, 1, 0}, fn ch, {ln, cl, acc} ->
        if acc >= offset do
          {:halt, {ln, cl, acc}}
        else
          acc2 = acc + byte_size(ch)

          cond do
            ch == "\n" -> {:cont, {ln + 1, 1, acc2}}
            true -> {:cont, {ln, cl + 1, acc2}}
          end
        end
      end)

    {line, col}
  end

  @doc false
  @spec build_snippet(String.t(), non_neg_integer(), non_neg_integer()) ::
          {String.t(), String.t()}
  defp build_snippet(src, line, col) do
    lines = String.split(src, "\n", trim: false)
    idx = max(line - 1, 0)
    current = Enum.at(lines, idx) || ""
    caret = String.duplicate(" ", max(col - 1, 0)) <> "^"
    {current, caret}
  end

  # Reducers
  def reduce_string(parts) do
    parts |> IO.iodata_to_binary()
  end

  def reduce_number(parts) do
    str = IO.iodata_to_binary(parts)

    if String.contains?(str, ".") do
      Decimal.new(str)
    else
      String.to_integer(str)
    end
  end

  def reduce_date([str]) do
    {:date, str}
  end

  def reduce_datetime([str]) do
    {:datetime, str}
  end

  def reduce_fun_call([name | rest]) do
    args =
      case rest do
        [args: args] -> args
        _ -> []
      end

    {:call, name, args}
  end

  def reduce_arith([lhs, op, rhs]) do
    {:arith, op, lhs, rhs}
  end

  def reduce_comp([lhs, op, rhs]) do
    {:cmp, op, lhs, rhs}
  end

  def reduce_set([{:binding_ref, name}, kind | list]) do
    values =
      case list do
        [] -> []
        [first | rest] -> [first | rest]
      end

    {:set, kind, name, List.wrap(values)}
  end

  def reduce_between([v, l, r]) do
    {:between, v, l, r}
  end

  def reduce_logical([]), do: nil

  def reduce_logical([first | rest]) do
    flat = [first | rest]

    case flat do
      [single] when is_list(single) ->
        single

      _ ->
        {tree, _} = Enum.reduce(rest, {first, nil}, &reduce_logical_term/2)
        tree
    end
  end

  defp reduce_logical_term(x, {acc, last_op}) do
    case x do
      :and -> {acc, :and}
      :or -> {acc, :or}
      term when last_op in [:and, :or] -> {{last_op, acc, term}, nil}
    end
  end

  def reduce_field_match([field, {:match_expr, expr}]) do
    {field, expr}
  end

  def reduce_atom([ident]), do: String.to_atom(ident)

  def reduce_fact_pattern(parts) do
    {binding, parts} =
      case parts do
        [binding, type | rest] -> {binding, [type | rest]}
        [type | rest] -> {nil, [type | rest]}
      end

    {type, fields} =
      case parts do
        [type, nil] ->
          {type, []}

        [type | rest] when is_list(rest) ->
          matches =
            rest
            |> Enum.flat_map(fn
              {:field_match, kv} -> [kv]
              {:match_expr, _} = me -> [me]
              {k, v} when is_binary(k) -> [{k, v}]
              list when is_list(list) -> list
              other -> [other]
            end)

          {type, matches}

        [type] ->
          {type, []}
      end

    {:fact, binding, type, Map.new(fields)}
  end

  def reduce_field_assign([field, value]) do
    {field, value}
  end

  def reduce_action([type | assigns]) do
    fields =
      assigns
      |> Enum.flat_map(fn
        {:field_assign, kv} -> [kv]
        list when is_list(list) -> list
        other -> [other]
      end)
      |> Map.new()

    {:emit, type, fields}
  end

  # reducers for accumulate
  def reduce_accumulate(parts) do
    {binding, parts} =
      case parts do
        [binding | rest] when is_binary(binding) -> {binding, rest}
        other -> {nil, other}
      end

    [{:fact, _b, _t, _f} = from | rest] = parts

    {group_by, rest} =
      case rest do
        [{:group_by, gb} | tail] -> {gb, tail}
        tail -> {[], tail}
      end

    {reducers, rest} =
      case rest do
        [{:reducers, rs} | tail] -> {rs, tail}
        tail -> {[], tail}
      end

    having =
      case rest do
        [having: expr] -> expr
        _ -> nil
      end

    {:accumulate, binding, from, group_by, reducers, having}
  end

  def reduce_named_reducer([name, {:sum, [expr]}]), do: {to_string(name), {:sum, expr}}
  def reduce_named_reducer([name, {:count}]), do: {to_string(name), {:count, nil}}
  def reduce_named_reducer([name, {:min, [expr]}]), do: {to_string(name), {:min, expr}}
  def reduce_named_reducer([name, {:max, [expr]}]), do: {to_string(name), {:max, expr}}
  def reduce_named_reducer([name, {:avg, [expr]}]), do: {to_string(name), {:avg, expr}}

  # reducers for exists/not
  def reduce_exists([{:fact, _b, _t, _f}] = [fact]), do: {:exists, fact}
  def reduce_not_exists([{:fact, _b, _t, _f}] = [fact]), do: {:not, {:exists, fact}}
  def reduce_not_fact([{:fact, _b, _t, _f}] = [fact]), do: {:not, fact}

  # Rule reducer builds AST node
  def reduce_rule([name | rest]) do
    {salience, rest2} =
      case rest do
        [s | tail] when is_integer(s) -> {s, tail}
        [s | tail] -> {s, tail}
        other -> {nil, other}
      end

    parts = Enum.flat_map(rest2, &List.wrap/1)

    when_block =
      Enum.find(parts, fn
        {:when, _} -> true
        _ -> false
      end)

    then_block =
      Enum.find(parts, fn
        {:then, _} -> true
        _ -> false
      end)

    %{name: name, salience: salience, when: when_block, then: then_block}
  end
end

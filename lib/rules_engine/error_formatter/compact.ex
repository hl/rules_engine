defmodule RulesEngine.ErrorFormatter.Compact do
  @moduledoc """
  Compact error formatter for single-line error messages.

  This formatter creates minimal, single-line error messages suitable
  for logging, CLI output, or situations where brevity is important.
  """

  @behaviour RulesEngine.ErrorFormatter

  @impl RulesEngine.ErrorFormatter
  def format_error(error) when is_map(error) do
    code = Map.get(error, :code, :unknown)
    message = Map.get(error, :message, "no message provided")
    path = Map.get(error, :path)

    base = "[#{code}] #{message}"
    location = format_location(path)
    position = format_position(error)

    [base, location, position]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @impl RulesEngine.ErrorFormatter
  def format_errors(errors) when is_list(errors) do
    case length(errors) do
      0 ->
        "No errors"

      1 ->
        format_error(List.first(errors))

      count ->
        formatted_errors =
          errors
          |> Enum.map(&format_error/1)
          |> Enum.join("; ")

        "#{count} errors: #{formatted_errors}"
    end
  end

  @impl RulesEngine.ErrorFormatter
  def format_error_with_context(error, context) do
    base_formatted = format_error(error)
    context_info = format_context_info(context)

    if context_info do
      "#{base_formatted} (#{context_info})"
    else
      base_formatted
    end
  end

  # Private helper functions

  defp format_location(nil), do: nil
  defp format_location([]), do: nil

  defp format_location(path) when is_list(path) do
    path_string =
      path
      |> Enum.map(&format_path_segment/1)
      |> Enum.join("->")

    "at #{path_string}"
  end

  defp format_location(path) do
    "at #{format_path_segment(path)}"
  end

  defp format_path_segment(segment) when is_binary(segment), do: segment
  defp format_path_segment(segment) when is_atom(segment), do: to_string(segment)
  defp format_path_segment(segment), do: inspect(segment)

  defp format_position(%{line: line, column: col}) when is_integer(line) do
    "#{line}:#{col}"
  end

  defp format_position(%{line: line}) when is_integer(line) do
    "#{line}"
  end

  defp format_position(_), do: nil

  defp format_context_info(%{tenant_id: tenant_id}) when is_binary(tenant_id) do
    "tenant: #{tenant_id}"
  end

  defp format_context_info(%{file_name: file_name}) when is_binary(file_name) do
    "file: #{Path.basename(file_name)}"
  end

  defp format_context_info(_), do: nil
end

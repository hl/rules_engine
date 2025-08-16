defmodule RulesEngine.ErrorFormatter.Default do
  @moduledoc """
  Default error formatter that provides human-readable text formatting.

  This formatter creates detailed, developer-friendly error messages
  with contextual information about error location and cause.
  """

  @behaviour RulesEngine.ErrorFormatter

  @impl RulesEngine.ErrorFormatter
  def format_error(error) when is_map(error) do
    code = Map.get(error, :code, :unknown)
    message = Map.get(error, :message, "no message provided")
    path = Map.get(error, :path)

    base_message = format_base_message(code, message)
    path_context = format_path_context(path)
    additional_info = format_additional_info(error) |> List.wrap() |> Enum.join("\n")

    [base_message, path_context, additional_info]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @impl RulesEngine.ErrorFormatter
  def format_errors(errors) when is_list(errors) do
    case length(errors) do
      0 ->
        "No errors found"

      1 ->
        format_error(List.first(errors))

      count ->
        header = "#{count} errors found:\n"

        formatted_errors =
          errors
          |> Enum.with_index(1)
          |> Enum.map(fn {error, index} ->
            formatted = format_error(error)
            "#{index}. #{formatted}"
          end)
          |> Enum.join("\n\n")

        header <> formatted_errors
    end
  end

  @impl RulesEngine.ErrorFormatter
  def format_error_with_context(error, context) when is_map(error) do
    base_formatted = format_error(error)

    context_info = format_context_info(context)

    if context_info do
      base_formatted <> "\n" <> context_info
    else
      base_formatted
    end
  end

  # Private helper functions

  defp format_base_message(code, message) do
    "Error [#{code}]: #{message}"
  end

  defp format_path_context(nil), do: nil
  defp format_path_context([]), do: nil

  defp format_path_context(path) when is_list(path) do
    path_string =
      path
      |> Enum.map(&format_path_segment/1)
      |> Enum.join(" -> ")

    "  Location: #{path_string}"
  end

  defp format_path_context(path) do
    "  Location: #{format_path_segment(path)}"
  end

  defp format_path_segment(segment) when is_binary(segment), do: segment
  defp format_path_segment(segment) when is_atom(segment), do: to_string(segment)
  defp format_path_segment(segment), do: inspect(segment)

  defp format_additional_info(error) when is_map(error) do
    info_parts = []

    info_parts =
      if line = Map.get(error, :line) do
        col = Map.get(error, :column, "")
        position_info = if col != "", do: "line #{line}, column #{col}", else: "line #{line}"
        ["  Position: #{position_info}" | info_parts]
      else
        info_parts
      end

    info_parts =
      if stage = Map.get(error, :stage) do
        ["  Stage: #{stage}" | info_parts]
      else
        info_parts
      end

    info_parts =
      if nested_errors = Map.get(error, :errors) do
        case length(nested_errors) do
          0 -> info_parts
          1 -> ["  Nested: 1 nested errors" | info_parts]
          count -> ["  Nested: #{count} nested errors" | info_parts]
        end
      else
        info_parts
      end

    info_parts =
      if details = Map.get(error, :details) do
        ["  Details: #{details}" | info_parts]
      else
        info_parts
      end

    info_parts =
      if issues = Map.get(error, :issues) do
        case length(issues) do
          0 -> info_parts
          count -> ["  Issues: #{count} integrity issues found" | info_parts]
        end
      else
        info_parts
      end

    case info_parts do
      [] -> nil
      parts -> Enum.reverse(parts) |> Enum.join("\n")
    end
  end

  defp format_additional_info(_error), do: nil

  defp format_context_info(context) when is_map(context) do
    context_parts = []

    context_parts =
      if tenant_id = Map.get(context, :tenant_id) do
        ["  Tenant: #{tenant_id}" | context_parts]
      else
        context_parts
      end

    context_parts =
      if file_name = Map.get(context, :file_name) do
        ["  File: #{file_name}" | context_parts]
      else
        context_parts
      end

    context_parts =
      if source = Map.get(context, :source_code) do
        truncated = String.slice(source, 0, 100)
        suffix = if String.length(source) > 100, do: "...", else: ""
        ["  Source: #{truncated}#{suffix}" | context_parts]
      else
        context_parts
      end

    case context_parts do
      [] -> nil
      parts -> Enum.reverse(parts) |> Enum.join("\n")
    end
  end

  defp format_context_info(_), do: nil
end

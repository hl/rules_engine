defmodule RulesEngine.ErrorFormatter.JSON do
  @moduledoc """
  JSON error formatter for API responses and structured logging.

  This formatter returns structured maps that can be easily serialized
  to JSON for API responses or structured logging systems.
  """

  @behaviour RulesEngine.ErrorFormatter

  @impl RulesEngine.ErrorFormatter
  def format_error(error) when is_map(error) do
    code = Map.get(error, :code, :unknown)
    message = Map.get(error, :message, "no message provided")
    path = Map.get(error, :path)

    %{
      type: "error",
      code: code,
      message: message,
      location: format_location(path),
      metadata: extract_metadata(error)
    }
    |> remove_nil_values()
  end

  @impl RulesEngine.ErrorFormatter
  def format_errors(errors) when is_list(errors) do
    %{
      type: "errors",
      count: length(errors),
      errors: Enum.map(errors, &format_error/1)
    }
  end

  @impl RulesEngine.ErrorFormatter
  def format_error_with_context(error, context) do
    error
    |> format_error()
    |> Map.put(:context, format_context(context))
    |> remove_nil_values()
  end

  # Private helper functions

  defp format_location(nil), do: nil
  defp format_location([]), do: nil

  defp format_location(path) when is_list(path) do
    %{
      path: Enum.map(path, &format_path_segment/1),
      path_string: Enum.join(Enum.map(path, &format_path_segment/1), " -> ")
    }
  end

  defp format_location(path) do
    %{
      path: [format_path_segment(path)],
      path_string: format_path_segment(path)
    }
  end

  defp format_path_segment(segment) when is_binary(segment), do: segment
  defp format_path_segment(segment) when is_atom(segment), do: to_string(segment)
  defp format_path_segment(segment), do: segment

  defp extract_metadata(error) do
    metadata = %{}

    metadata =
      if line = Map.get(error, :line) do
        Map.put(metadata, :position, %{line: line, column: Map.get(error, :column)})
      else
        metadata
      end

    metadata =
      if stage = Map.get(error, :stage) do
        Map.put(metadata, :stage, stage)
      else
        metadata
      end

    metadata =
      if errors = Map.get(error, :errors) do
        Map.put(metadata, :nested_errors, %{count: length(errors), errors: errors})
      else
        metadata
      end

    metadata =
      if details = Map.get(error, :details) do
        Map.put(metadata, :details, details)
      else
        metadata
      end

    metadata =
      if issues = Map.get(error, :issues) do
        Map.put(metadata, :issues, %{count: length(issues)})
      else
        metadata
      end

    if map_size(metadata) > 0, do: metadata, else: nil
  end

  defp format_context(context) when is_map(context) do
    formatted = %{}

    formatted =
      if tenant_id = Map.get(context, :tenant_id) do
        Map.put(formatted, :tenant_id, tenant_id)
      else
        formatted
      end

    formatted =
      if file_name = Map.get(context, :file_name) do
        Map.put(formatted, :file_name, file_name)
      else
        formatted
      end

    formatted =
      if source = Map.get(context, :source_code) do
        # Include truncated source for context
        truncated_source = String.slice(source, 0, 200)
        Map.put(formatted, :source_preview, truncated_source)
      else
        formatted
      end

    if map_size(formatted) > 0, do: formatted, else: nil
  end

  defp format_context(_), do: nil

  defp remove_nil_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end

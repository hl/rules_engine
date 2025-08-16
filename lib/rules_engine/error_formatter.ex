defmodule RulesEngine.ErrorFormatter do
  @moduledoc """
  Behaviour for customizing error formatting in RulesEngine.

  Host applications can implement this behaviour to customize how 
  parsing, validation, and compilation errors are presented to users.

  ## Error Structure

  All RulesEngine errors follow this structure:
  - `code`: Atom identifying the error type (e.g., `:unknown_binding`, `:parse_error`)
  - `message`: Human-readable error message
  - `path`: Path context (e.g., rule name, field path) for error location
  - Additional fields may be present for specific error types

  ## Usage

  Configure a custom formatter in your application:

      config :rules_engine, :error_formatter, MyApp.CustomErrorFormatter

  ## Built-in Formatters

  - `RulesEngine.ErrorFormatter.Default` - Standard text formatting
  - `RulesEngine.ErrorFormatter.JSON` - Structured JSON formatting
  - `RulesEngine.ErrorFormatter.Compact` - Minimal single-line formatting
  """

  @type error :: map()

  @type formatted_error :: String.t() | map() | term()

  @doc """
  Format a single error for display.

  Returns a formatted representation of the error suitable for the target audience.
  This could be a string for human consumption, a structured map for APIs,
  or any other format appropriate for your application.
  """
  @callback format_error(error :: error()) :: formatted_error()

  @doc """
  Format multiple errors for display.

  By default, formats each error individually and combines them,
  but implementations can override this for custom aggregation logic.
  """
  @callback format_errors(errors :: [error()]) :: formatted_error()

  @doc """
  Optional callback to include additional context in error formatting.

  Context might include source code, tenant information, or other
  application-specific data that helps with error presentation.
  """
  @callback format_error_with_context(error :: error(), context :: map()) :: formatted_error()

  @optional_callbacks format_error_with_context: 2

  @doc """
  Format a single error using the configured formatter.
  """
  @spec format_error(error()) :: formatted_error()
  def format_error(error) do
    formatter = get_formatter()
    formatter.format_error(error)
  end

  @doc """
  Format multiple errors using the configured formatter.
  """
  @spec format_errors([error()]) :: formatted_error()
  def format_errors(errors) do
    formatter = get_formatter()
    formatter.format_errors(errors)
  end

  @doc """
  Format a single error with additional context using the configured formatter.
  """
  @spec format_error_with_context(error(), map()) :: formatted_error()
  def format_error_with_context(error, context \\ %{}) do
    formatter = get_formatter()

    if function_exported?(formatter, :format_error_with_context, 2) do
      formatter.format_error_with_context(error, context)
    else
      formatter.format_error(error)
    end
  end

  @doc """
  Get the currently configured error formatter.
  """
  @spec get_formatter() :: module()
  def get_formatter do
    Application.get_env(:rules_engine, :error_formatter, RulesEngine.ErrorFormatter.Default)
  end

  @doc """
  Dynamically set the error formatter for testing or runtime configuration.
  """
  @spec set_formatter(module()) :: :ok
  def set_formatter(formatter) when is_atom(formatter) do
    Application.put_env(:rules_engine, :error_formatter, formatter)
    :ok
  end
end

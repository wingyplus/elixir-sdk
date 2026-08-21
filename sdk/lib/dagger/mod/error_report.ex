defmodule Dagger.Mod.ErrorReport do
  @moduledoc false

  # Turns a failed function call into a `Dagger.Error` and hands it back to the
  # engine through `FunctionCall.returnError`, the way the Go, Python and
  # TypeScript SDKs do. The engine then renders it as a proper error object in
  # the TUI and in Cloud instead of an opaque non-zero exit.

  alias Dagger.Core.ExecError
  alias Dagger.Core.GraphQL.Response

  # OpenTelemetry exception attribute names, reused for consistency with the
  # other SDKs.
  @exception_type "exception.type"
  @exception_message "exception.message"
  @exception_stacktrace "exception.stacktrace"

  # Reporting runs against a session that is, by definition, in the middle of
  # failing, and the client's own `query_timeout` defaults to `:infinity`. Bound
  # the queries the report costs: a report that cannot get through has to give
  # way to the stderr fallback rather than hang the call it is failing.
  @query_timeout :timer.seconds(30)

  @doc """
  Report a failure to the engine as a `Dagger.Error`.

  `kind` and `reason` are the pair `try/1` hands a `rescue` or `catch` clause;
  a function that merely returned `{:error, reason}` is reported as `:error`
  with no stacktrace.
  """
  def report(dag, kind, reason, stacktrace) do
    {message, values} = describe(kind, reason, stacktrace)
    dag = bound_queries(dag)

    error =
      values
      |> Enum.sort()
      |> Enum.reduce(Dagger.Client.error(dag, message), fn {name, value}, error ->
        Dagger.Error.with_value(error, name, encode_value(value))
      end)

    dag
    |> Dagger.Client.current_function_call()
    |> Dagger.FunctionCall.return_error(error)
  end

  defp bound_queries(dag) do
    update_in(dag.client.connect_opts, &Keyword.put(&1, :query_timeout, @query_timeout))
  end

  @doc """
  Describe a failure as an error message and the values to attach to it.

  An API error keeps its own message and carries its `extensions` through, so
  that the details of - say - a `Dagger.Core.ExecError` raised in a nested call
  survive crossing the module boundary.
  """
  def describe(kind, reason, stacktrace \\ nil)

  def describe(:error, %ExecError{original_error: %Response.Error{} = original} = error, stack) do
    {safe_message(error), error |> exception_values(stack) |> merge_extensions(original)}
  end

  def describe(:error, %Response.Error{} = error, stack) do
    {safe_message(error), error |> exception_values(stack) |> merge_extensions(error)}
  end

  def describe(:error, %{__exception__: true} = exception, stack) do
    values = exception_values(exception, stack)
    {"#{values[@exception_type]}: #{values[@exception_message]}", values}
  end

  def describe(:error, reason, stack) when is_binary(reason) or is_atom(reason) do
    {to_string(reason), put_stacktrace(%{}, stack)}
  end

  def describe(:error, reason, stack) do
    {inspect(reason), put_stacktrace(%{}, stack)}
  end

  def describe(kind, reason, stack) do
    values =
      put_stacktrace(
        %{@exception_type => to_string(kind), @exception_message => inspect(reason)},
        stack
      )

    {Exception.format_banner(kind, reason), values}
  end

  @doc """
  Encode a value as `Dagger.JSON`, falling back to its `inspect/1` form when it
  has no JSON representation - a value the error handler cannot encode must not
  turn the error being reported into a crash.
  """
  def encode_value(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      {:error, _} -> Jason.encode!(inspect(value))
    end
  end

  defp exception_values(exception, stacktrace) do
    %{
      @exception_type => inspect(exception.__struct__),
      @exception_message => safe_message(exception)
    }
    |> put_stacktrace(stacktrace)
  end

  defp put_stacktrace(values, stacktrace) when stacktrace in [nil, []], do: values

  defp put_stacktrace(values, stacktrace) do
    Map.put(values, @exception_stacktrace, Exception.format_stacktrace(stacktrace))
  end

  defp merge_extensions(values, %Response.Error{extensions: extensions})
       when is_map(extensions) do
    Map.merge(values, extensions)
  end

  defp merge_extensions(values, _error), do: values

  # The last thing a failing call should do is fail again while describing why.
  defp safe_message(exception) do
    Exception.message(exception)
  rescue
    _ -> inspect(exception)
  end
end

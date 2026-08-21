defmodule Dagger.Mod do
  @moduledoc false

  alias Dagger.Core.Client
  alias Dagger.Core.QueryBuilder, as: QB
  alias Dagger.Mod.Encoder
  alias Dagger.Mod.ErrorReport
  alias Dagger.Mod.Scope
  alias Dagger.Mod.Registry

  @doc """
  Invoke a function.
  """
  def invoke(module) when is_atom(module) do
    case Dagger.Global.start_link() do
      {:ok, _} -> invoke(Dagger.Global.dag(), module)
      otherwise -> otherwise
    end
  end

  def invoke(dag, module) do
    # A module function fails in three ways - it returns `{:error, reason}`, it
    # raises, or it throws/exits - and all three have to reach the engine as a
    # `Dagger.Error`. Only `rescue`/`catch` can see a stacktrace, so the whole
    # dispatch is wrapped; the reporting itself happens outside the `try` so
    # that the exit below is not caught by it.
    result =
      try do
        with {:ok, scope} <- current_scope(dag),
             {:ok, json} <- invoke(dag, module, scope) do
          return_value(dag, json)
        else
          {:error, reason} -> {:failed, :error, reason, nil}
        end
      rescue
        exception -> {:failed, :error, exception, __STACKTRACE__}
      catch
        kind, reason -> {:failed, kind, reason, __STACKTRACE__}
      end

    case result do
      {:failed, kind, reason, stacktrace} -> fail(dag, kind, reason, stacktrace)
      otherwise -> otherwise
    end
  after
    Dagger.Global.close()
  end

  # Register module.
  def invoke(dag, module, %Scope{parent_name: ""}) do
    dag
    |> Dagger.Mod.Module.define(module)
    |> Encoder.validate_and_encode(Dagger.Module)
  end

  # Constructor call.
  def invoke(dag, module, %Scope{fn_name: ""} = scope) do
    fun_def = module.__object__(:function, :init)
    args = Scope.args!(scope, fun_def.args, dag)
    return_type = fun_def.return

    execute_function(module, :init, args, return_type)
  end

  # Invoke function.
  def invoke(dag, root_module, %Scope{} = scope) do
    registry = Registry.register(root_module)
    module = Registry.get_module_by_name!(registry, scope.parent_name)
    {:ok, parent} = Scope.into_module(scope, module, dag)
    fun_name = Scope.fn_name(scope)
    fun_def = module.__object__(:function, fun_name)

    args =
      scope
      |> Scope.args!(fun_def.args, dag)
      |> then(fn args ->
        if(fun_def.self, do: [parent | args], else: args)
      end)

    return_type = fun_def.return

    execute_function(module, fun_name, args, return_type)
  end

  # The call being served, in one round-trip. The arguments are selected inline
  # rather than by id so that the whole scope - the parent, the function name
  # and every argument - arrives with the response instead of costing a query
  # apiece.
  defp current_scope(dag) do
    query_builder =
      dag.query_builder
      |> QB.select("currentFunctionCall")
      |> QB.select_fields(["parentName", "name", "parent", {"inputArgs", ["name", "value"]}])

    with {:ok, fn_call} <- Client.execute(dag.client, query_builder) do
      {:ok, Scope.from_fn_call(fn_call)}
    end
  end

  # `returnValue` is a `Void`, so there is nothing to unwrap from the response.
  defp return_value(dag, json) do
    query_builder =
      dag.query_builder
      |> QB.select("currentFunctionCall")
      |> QB.select("returnValue", value: json)

    case Client.execute(dag.client, query_builder) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp execute_function(module, fun_name, args, return_type) do
    case apply(module, fun_name, args) do
      {:error, _} = error -> error
      {:ok, result} -> Encoder.validate_and_encode(result, return_type)
      result -> Encoder.validate_and_encode(result, return_type)
    end
  end

  # Hand the failure to the engine, then exit non-zero the way the Go, Python
  # and TypeScript SDKs do - `returnError` records the error, it does not end
  # the call.
  defp fail(dag, kind, reason, stacktrace) do
    case report(dag, kind, reason, stacktrace) do
      :ok ->
        # A crash keeps its stacktrace on the function's stderr as well: the
        # values of a `Dagger.Error` are not rendered by every frontend, and a
        # trace is what makes the failure debuggable.
        if stacktrace, do: IO.puts(:stderr, Exception.format(kind, reason, stacktrace))

      {:error, report_error} ->
        {message, _values} = ErrorReport.describe(kind, reason, stacktrace)
        {report_message, _values} = ErrorReport.describe(:error, report_error)
        IO.puts(:stderr, "failed to return error: #{report_message}")
        IO.puts(:stderr, "original error: #{message}")
    end

    exit({:shutdown, 2})
  end

  # Reporting talks to the engine, so it can fail - or raise, when the session
  # is already gone - on its own. Either way the original failure is what the
  # caller needs to hear about.
  defp report(dag, kind, reason, stacktrace) do
    ErrorReport.report(dag, kind, reason, stacktrace)
  rescue
    exception -> {:error, exception}
  end
end

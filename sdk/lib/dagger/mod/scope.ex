defmodule Dagger.Mod.Scope do
  @moduledoc false

  defstruct [
    # A parent need to convert into module.
    :parent_name,
    # Data of the parent.
    :parent_json,
    # A function to invoke.
    :fn_name,
    # The arguments of the function.
    :input_args
  ]

  @doc """
  Build the scope from a `currentFunctionCall` response.

  The caller selects the whole call at once, so the fields come in already
  decoded, keyed by the schema's own names.
  """
  def from_fn_call(%{} = fn_call) do
    %__MODULE__{
      parent_name: fn_call["parentName"],
      parent_json: fn_call["parent"],
      fn_name: fn_call["name"],
      input_args: fn_call["inputArgs"]
    }
  end

  def fn_name(%__MODULE__{} = scope) do
    scope.fn_name |> Macro.underscore() |> String.to_existing_atom()
  end

  def args!(%__MODULE__{} = scope, arg_defs, dag) do
    scope.input_args
    |> fetch_args!()
    |> decode_args!(arg_defs, dag)
  end

  def into_module(%__MODULE__{} = scope, module, dag) do
    Dagger.Mod.Decoder.decode(scope.parent_json, {:optional, module}, dag)
  end

  defp fetch_args!(input_args) do
    Enum.into(input_args, %{}, fn %{"name" => name, "value" => value} ->
      {Macro.underscore(name), value}
    end)
  end

  # Get the value from a given `input_args` and make it positional by `args_def`.
  def decode_args!(input_args, arg_defs, dag) do
    for {name, arg_def} <- arg_defs do
      {:ok, value} =
        input_args
        |> Map.get(to_string(name))
        |> Dagger.Mod.Decoder.decode(arg_def[:type], dag)

      value
    end
  end
end

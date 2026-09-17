defmodule Dagger.Mod.Decoder do
  @moduledoc """
  Provides set of functions for decoding value from function call.
  """

  alias Dagger.Core.QueryBuilder, as: QB

  @doc """
  Decode the given `value` into a proper `type`.
  """
  def decode(value, type, dag)

  def decode(nil, type, dag) do
    cast(nil, type, dag)
  end

  def decode(value, type, dag) do
    with {:ok, value} <- JSON.decode(value) do
      cast(value, type, dag)
    end
  end

  defp cast(value, :integer, _) when is_integer(value) do
    {:ok, value}
  end

  defp cast(value, :float, _) when is_float(value) do
    {:ok, value}
  end

  # JSON has one number type, so a whole float can come back without a fraction.
  defp cast(value, :float, _) when is_integer(value) do
    {:ok, value / 1}
  end

  defp cast(value, :boolean, _) when is_boolean(value) do
    {:ok, value}
  end

  defp cast(value, :string, _) when is_binary(value) do
    {:ok, value}
  end

  defp cast(values, {:list, type}, dag) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case cast(value, type, dag) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp cast(nil, {:optional, _type}, _dag), do: {:ok, nil}
  defp cast(value, {:optional, type}, dag), do: cast(value, type, dag)

  defp cast(value, module, dag) when (is_map(value) or is_binary(value)) and is_atom(module) do
    Code.ensure_loaded!(module)

    case module.__kind__() do
      :object ->
        if function_exported?(module, :__struct__, 0) do
          to_struct(value, module, dag)
        else
          {:ok, value}
        end

      :enum ->
        if function_exported?(module, :__enum__, 2) do
          {:ok, module.__enum__(:key, value)}
        else
          {:ok, value}
        end

      :scalar ->
        {:ok, value}
    end
  end

  defp cast(value, type, _) do
    {:error, "Cannot cast value #{inspect(value)} to type #{inspect(type)}."}
  end

  # An object from the API arrives as its id, and is loaded back through `node`.
  defp to_struct(id, module, dag) when is_binary(id) do
    query_builder =
      dag.query_builder
      |> QB.select("node", id: id)
      |> QB.inline_fragment(module.__name__())

    {:ok, struct(module, query_builder: query_builder, client: dag.client)}
  end

  # A module's own object arrives as its fields. A field that is absent or null
  # keeps the struct's default.
  defp to_struct(map, module, dag) when is_map(map) do
    Enum.reduce_while(module.__object__(:fields), {:ok, []}, fn {name, field_def}, {:ok, acc} ->
      case Map.get(map, Atom.to_string(name)) do
        nil ->
          {:cont, {:ok, acc}}

        value ->
          case cast(value, field_def.type, dag) do
            {:ok, value} -> {:cont, {:ok, [{name, value} | acc]}}
            {:error, _} = error -> {:halt, error}
          end
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, struct(module, fields)}
      error -> error
    end
  end
end

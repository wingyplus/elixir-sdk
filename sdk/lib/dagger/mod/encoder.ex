defmodule Dagger.Mod.Encoder do
  @moduledoc """
  Provides set of functions for encoding value from function call.
  """

  @doc """
  Validate the given `value` and encoding it.
  """
  def validate_and_encode(value, type) do
    with {:ok, value} <- validate(value, type),
         {:ok, value} <- put_ids(value) do
      encode(value)
    end
  end

  # A Dagger object is returned as its id, which its `Jason.Encoder` fetches
  # with a round-trip of its own - one for every object in a list, or in the
  # fields of a returned object. The ids of all of them are fetched together
  # instead, and put in their place before encoding.
  defp put_ids(value) do
    case collect_objects(value, []) do
      [] ->
        {:ok, value}

      objects ->
        with {:ok, ids} <- Dagger.Mod.ID.load(objects) do
          {:ok, put_ids(value, ids)}
        end
    end
  end

  defp collect_objects(value, acc) when is_list(value) do
    Enum.reduce(value, acc, &collect_objects/2)
  end

  defp collect_objects(%_{} = value, acc) do
    if dagger_object?(value) do
      [value | acc]
    else
      value |> Map.from_struct() |> collect_objects(acc)
    end
  end

  defp collect_objects(value, acc) when is_map(value) do
    value |> Map.values() |> collect_objects(acc)
  end

  defp collect_objects(_value, acc), do: acc

  defp put_ids(value, ids) when is_list(value), do: Enum.map(value, &put_ids(&1, ids))

  defp put_ids(value, ids) when is_map(value) do
    case ids do
      %{^value => id} -> id
      # Replacing the fields keeps a struct's `__struct__`, so it encodes as before.
      _ -> Map.merge(value, Map.new(Map.to_list(value), fn {k, v} -> {k, put_ids(v, ids)} end))
    end
  end

  defp put_ids(value, _ids), do: value

  # The objects of the API: structs deriving `Dagger.ID` that fetch their id by
  # querying it.
  defp dagger_object?(value) do
    Dagger.ID.impl_for(value) not in [nil, Dagger.ID.Any] and
      Map.has_key?(value, :query_builder) and Map.has_key?(value, :client)
  end

  defp validate(value, :integer) when is_integer(value) do
    {:ok, value}
  end

  defp validate(value, :float) when is_float(value) do
    {:ok, value}
  end

  defp validate(value, :boolean) when is_boolean(value) do
    {:ok, value}
  end

  defp validate(value, :string) when is_binary(value) do
    {:ok, value}
  end

  defp validate(values, {:list, type}) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case validate(value, type) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp validate(_value, Dagger.Void) do
    {:ok, nil}
  end

  defp validate(%module{} = value, module) do
    {:ok, value}
  end

  # The engine looks a returned enum member up by the name it was registered
  # under, which is its key.
  defp validate(key, module) when is_atom(key) and is_atom(module) do
    if enum?(module) and key in Dagger.Mod.Enum.keys(module) do
      {:ok, Atom.to_string(key)}
    else
      {:error, %Dagger.Mod.TypeMismatchError{value: key, type: module}}
    end
  end

  defp validate(value, type) do
    {:error, %Dagger.Mod.TypeMismatchError{value: value, type: type}}
  end

  defp enum?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__kind__, 0) and
      module.__kind__() == :enum
  end

  defp encode(value) do
    Jason.encode(value)
  end
end

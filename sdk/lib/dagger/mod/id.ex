defmodule Dagger.Mod.ID do
  @moduledoc false

  # An id that has already been fetched from the engine.
  #
  # Every object a registration hands to the API - a type, a function, an
  # object - goes by id, and `Dagger.ID.id!/1` fetches one with a round-trip of
  # its own. Registration fetches them in bulk with `load!/2` instead, and
  # passes this in place of the object, so that handing it over costs nothing.
  # A function's return value fetches its objects' ids in bulk with `load/1`.

  alias Dagger.Core.Client
  alias Dagger.Core.QueryBuilder, as: QB

  defstruct [:id]

  @doc """
  Fetch the ids of `resources` in a single round-trip, in order.
  """
  def load!(_dag, []), do: []

  def load!(%Dagger.Client{} = dag, resources) do
    selections = Enum.map(resources, &QB.select(&1.query_builder, "id"))
    {:ok, ids} = Client.execute_all(dag.client, selections)
    Enum.map(ids, &%__MODULE__{id: &1})
  end

  @doc """
  Fetch the ids of `resources`, a round-trip for each client they come from.

  Returns a map from each resource to its id, or the first error a request ran
  into.
  """
  def load(resources) do
    resources
    |> Enum.uniq()
    |> Enum.group_by(& &1.client)
    |> Enum.reduce_while({:ok, %{}}, fn {client, resources}, {:ok, ids} ->
      selections = Enum.map(resources, &QB.select(&1.query_builder, "id"))

      case Client.execute_all(client, selections) do
        {:ok, loaded} -> {:cont, {:ok, Map.merge(ids, Map.new(Enum.zip(resources, loaded)))}}
        error -> {:halt, error}
      end
    end)
  end

  defimpl Dagger.ID do
    def id!(%{id: id}), do: id
  end
end

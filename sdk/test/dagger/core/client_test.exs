defmodule Dagger.Core.ClientTest do
  use ExUnit.Case, async: true

  alias Dagger.Core.Client
  alias Dagger.Core.QueryBuilder, as: QB

  # Connects to a live engine in setup_all.
  @moduletag :integration

  setup_all do
    dag = Dagger.connect!(connect_timeout: :timer.seconds(60))
    on_exit(fn -> Dagger.close(dag) end)

    %{dag: dag}
  end

  describe "execute_all/2" do
    test "return each result in the order of the selections", %{dag: dag} do
      kinds = [:STRING_KIND, :INTEGER_KIND]

      selections =
        for kind <- kinds do
          dag.query_builder
          |> QB.select("typeDef")
          |> QB.select("withKind", kind: kind)
          |> QB.select("kind")
        end

      assert Client.execute_all(dag.client, selections) ==
               {:ok, ["STRING_KIND", "INTEGER_KIND"]}
    end

    test "return the result of a leaf field set as a map", %{dag: dag} do
      selection =
        dag.query_builder
        |> QB.select("typeDef")
        |> QB.select("withKind", kind: :BOOLEAN_KIND)
        |> QB.select_fields(["kind", "optional"])

      assert Client.execute_all(dag.client, [selection]) ==
               {:ok, [%{"kind" => "BOOLEAN_KIND", "optional" => false}]}
    end

    test "return an error when a selection fails", %{dag: dag} do
      good = dag.query_builder |> QB.select("typeDef") |> QB.select("kind")
      bad = dag.query_builder |> QB.select("container") |> QB.select("noSuchField")

      assert {:error, _} = Client.execute_all(dag.client, [good, bad])
    end
  end
end

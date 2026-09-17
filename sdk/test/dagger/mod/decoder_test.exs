defmodule Dagger.Mod.DecoderTest do
  use Dagger.DagCase

  alias Dagger.Mod.Decoder

  describe "decode/2" do
    test "decode primitive type", %{dag: dag} do
      assert {:ok, "hello"} = Decoder.decode(json("hello"), :string, dag)
      assert {:ok, 1} = Decoder.decode(json(1), :integer, dag)
      assert {:ok, 2.0} = Decoder.decode(json(2.0), :float, dag)
      assert {:ok, true} = Decoder.decode(json(true), :boolean, dag)
      assert {:ok, false} = Decoder.decode(json(false), :boolean, dag)
    end

    test "decode list", %{dag: dag} do
      assert {:ok, [1, 2, 3]} =
               Decoder.decode(json([1, 2, 3]), {:list, :integer}, dag)
    end

    test "decode optional", %{dag: dag} do
      assert {:ok, nil} = Decoder.decode(nil, {:optional, :string}, dag)
      assert {:ok, "hello"} = Decoder.decode(json("hello"), {:optional, :string}, dag)
    end

    test "decode id to struct", %{dag: dag} do
      assert {:ok, %Dagger.Container{} = container} =
               Decoder.decode(json(container_id(dag)), Dagger.Container, dag)

      # Ensure the client (`dag`) is passed through to the struct.
      assert {:ok, _} = Dagger.Container.sync(container)
    end

    test "decode struct fields by their declared types", %{dag: dag} do
      id = container_id(dag)

      assert {:ok,
              %ObjectDecodeFields{
                objects: [%ObjectField{name: "a"}, %ObjectField{name: "b"}],
                containers: [%Dagger.Container{} = container],
                level: :high,
                ratio: 2.0,
                note: nil
              }} =
               Decoder.decode(
                 json(%{
                   "objects" => [%{"name" => "a"}, %{"name" => "b"}],
                   "containers" => [id],
                   "level" => "high",
                   "ratio" => 2,
                   "note" => nil,
                   "unknown" => "ignored"
                 }),
                 ObjectDecodeFields,
                 dag
               )

      assert {:ok, _} = Dagger.Container.sync(container)
    end

    test "decode struct with a field of the wrong type", %{dag: dag} do
      assert {:error, _} =
               Decoder.decode(json(%{"objects" => [%{"name" => 1}]}), ObjectDecodeFields, dag)
    end

    test "decode struct", %{dag: dag} do
      assert {:ok, %ObjectDecoder{value: "v", object_field: %ObjectField{name: "dag"}}} =
               Decoder.decode(
                 json(%{"value" => "v", "object_field" => %{"name" => "dag"}}),
                 ObjectDecoder,
                 dag
               )

      assert {:ok, %ObjectDecodeId{}} =
               Decoder.decode(json(%{container: container_id(dag)}), ObjectDecodeId, dag)
    end

    test "decode error", %{dag: dag} do
      assert {:error, _} = Decoder.decode(json(1), :string, dag)
    end

    test "decode enum", %{dag: dag} do
      assert {:ok, :unknown} = Decoder.decode(json("unknown"), SimpleEnum, dag)
    end

    test "decode enum with a custom member value", %{dag: dag} do
      # The engine names a member by its key, so that -- not the declared wire
      # value -- is the string that comes back.
      assert {:ok, :UNKNOWN} = Decoder.decode(json("UNKNOWN"), EnumAliasValue, dag)
      assert {:ok, :LOW} = Decoder.decode(json("LOW"), EnumAliasValue, dag)
    end
  end

  defp json(value), do: JSON.encode!(value)

  defp container_id(dag) do
    {:ok, container_id} = dag |> Dagger.Client.container() |> Dagger.Container.id()
    container_id
  end
end

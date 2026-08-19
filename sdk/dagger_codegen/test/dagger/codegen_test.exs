defmodule Dagger.CodegenTest do
  use ExUnit.Case, async: true

  alias Dagger.Codegen
  alias Dagger.Codegen.Introspection.Types.Schema

  defp schema(types) do
    Schema.from_map(%{"queryType" => %{"name" => "Query"}, "types" => types})
  end

  defp type(kind, name, extra \\ %{}) do
    Map.merge(%{"kind" => kind, "name" => name}, extra)
  end

  describe "index/1" do
    test "reports each type's kind, which is how an @expectedType is resolved" do
      index =
        schema([
          type("OBJECT", "Container"),
          type("INTERFACE", "Node"),
          type("INPUT_OBJECT", "BuildArg"),
          type("SCALAR", "Platform")
        ])
        |> Codegen.index()

      assert index["Container"].kind == :object
      assert index["Node"].kind == :interface
      assert index["BuildArg"].kind == :input
      assert index["Platform"].kind == :scalar
    end

    test "carries enum members, which is what an enum argument is guarded against" do
      index =
        schema([
          type("ENUM", "CacheSharingMode", %{
            "enumValues" => [
              %{
                "name" => "SHARED",
                "description" => "",
                "isDeprecated" => false,
                "deprecationReason" => nil
              },
              %{
                "name" => "PRIVATE",
                "description" => "",
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ]
          })
        ])
        |> Codegen.index()

      assert index["CacheSharingMode"] == %{kind: :enum, enum_values: ["SHARED", "PRIVATE"]}
    end
  end

  describe "types/1" do
    test "skips introspection's own types and the scalars that map onto Elixir builtins" do
      names =
        schema([
          type("OBJECT", "Container"),
          type("OBJECT", "__Schema"),
          type("SCALAR", "String"),
          type("SCALAR", "ID"),
          type("SCALAR", "Platform")
        ])
        |> Codegen.types()
        |> Enum.map(& &1.name)

      assert names == ["Container", "Platform"]
    end

    test "sorts fields, so generated functions read alphabetically" do
      field = fn name ->
        %{
          "name" => name,
          "description" => "",
          "isDeprecated" => false,
          "deprecationReason" => nil,
          "args" => [],
          "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil}
        }
      end

      [container] =
        schema([type("OBJECT", "Container", %{"fields" => [field.("stdout"), field.("from")]})])
        |> Codegen.types()

      assert Enum.map(container.fields, & &1.name) == ["from", "stdout"]
    end
  end
end

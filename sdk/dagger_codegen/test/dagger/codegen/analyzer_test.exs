defmodule Dagger.Codegen.AnalyzerTest do
  use ExUnit.Case, async: true

  alias Dagger.Codegen.Analyzer
  alias Dagger.Codegen.IR.ModuleDef
  alias Dagger.Codegen.Introspection.Types.Type

  defp analyze(fixture, kinds \\ %{}) do
    "test/fixtures/#{fixture}.json"
    |> File.read!()
    |> JSON.decode!()
    |> Type.from_map()
    |> Analyzer.analyze(kinds)
  end

  defp function(mod, name), do: Enum.find(mod.functions, &(&1.name == name))

  defp synthetic(map), do: map |> Type.from_map() |> Analyzer.analyze()

  defp non_null(inner), do: %{"kind" => "NON_NULL", "name" => nil, "ofType" => inner}

  test "names the GraphQL root after the client" do
    mod = analyze("objects/chain-selection")

    assert mod.module == "Dagger.Client"
    assert mod.var == "client"
    assert mod.gql_name == "Query"
    assert mod.kind == :object
  end

  test "derives the id-based protocols from the fields that exist" do
    assert analyze("objects/gen-protocol").derives == ["Dagger.ID", "Dagger.Sync"]
    assert analyze("objects/iss-7788").derives == ["Dagger.Sync"]
    assert analyze("objects/chain-selection").derives == []

    refute ModuleDef.node?(analyze("objects/chain-selection"))
    assert ModuleDef.node?(analyze("objects/gen-protocol"))
  end

  test "keeps the type's description as the moduledoc" do
    assert analyze("scalars/platform").moduledoc ==
             "The platform config OS and architecture in a Container."
  end

  test "falls back to the module's own name when a type has no description" do
    # ExDoc drops a module with no @moduledoc, so there is always one.
    assert synthetic(%{"kind" => "SCALAR", "name" => "Platform", "description" => ""}).moduledoc ==
             "Dagger.Platform"
  end

  describe "return classification" do
    test "an object is lazy — no request is made" do
      assert function(analyze("objects/chain-selection"), "type_def").return ==
               {:lazy, {:object, "TypeDef"}}
    end

    test "a scalar is a leaf" do
      assert function(analyze("objects/execute-leaf-node"), "name").return == {:leaf, :string}
    end

    test "a list of objects is fetched by id" do
      assert function(analyze("objects/list-leaf-nodes"), "env_variables").return ==
               {:nodes, {:list, {:object, "EnvVariable"}}}
    end

    test "Void is executed for effect" do
      assert function(analyze("objects/return-void"), "return_value").return == :void
    end

    test "a list of enums is mapped back from the wire" do
      assert function(analyze("objects/return-list-of-enums"), "permissions").return ==
               {:list_of_enum, {:list, {:enum, "GhaPermission"}}}
    end

    test "a scalar whose @expectedType is its own type hands back the object" do
      assert function(analyze("objects/iss-7788"), "sync").return == {:node, "Container"}
    end
  end

  describe "arguments" do
    test "splits required from optional by nullability" do
      fun = function(analyze("objects/id-arg"), "generated_code")

      assert Enum.map(fun.required_args, & &1.name) == ["code"]
      assert fun.optional_args == []
    end

    test "an ID argument takes the type its @expectedType names" do
      fun =
        function(analyze("objects/id-arg", %{"Directory" => %{kind: :object}}), "generated_code")

      assert [%{name: "code", gql_name: "code", type: {:object, "Directory"}}] = fun.required_args
    end

    test "an unknown @expectedType degrades to the permissive guard, never a bad struct match" do
      fun = function(analyze("objects/id-arg"), "generated_code")

      assert [%{type: {:interface, "Directory"}, guard: {:call, "is_struct"}}] = fun.required_args
    end

    test "@expectedType resolves against the schema's kinds, so interfaces stay interfaces" do
      fun =
        function(
          analyze("objects/id-arg", %{"Directory" => %{kind: :interface}}),
          "generated_code"
        )

      assert [%{type: {:interface, "Directory"}}] = fun.required_args
    end

    test "the receiver is named after its type" do
      assert function(analyze("objects/iss-8610"), "with_directory").self == "directory"
      assert function(analyze("objects/chain-selection"), "type_def").self == "client"
    end

    test "the receiver yields when a required argument shares its name" do
      mod =
        synthetic(%{
          "kind" => "OBJECT",
          "name" => "Container",
          "description" => "A container.",
          "fields" => [
            %{
              "name" => "withContainer",
              "description" => "",
              "deprecationReason" => nil,
              "type" => non_null(%{"kind" => "OBJECT", "name" => "Container", "ofType" => nil}),
              "args" => [
                %{
                  "name" => "container",
                  "description" => "",
                  "defaultValue" => nil,
                  "type" => non_null(%{"kind" => "SCALAR", "name" => "String", "ofType" => nil})
                }
              ]
            }
          ]
        })

      assert function(mod, "with_container").self == "container_"
    end
  end

  describe "guards" do
    @index %{
      "Directory" => %{kind: :object, enum_values: []},
      "Node" => %{kind: :interface, enum_values: []},
      "CacheSharingMode" => %{kind: :enum, enum_values: ["SHARED", "PRIVATE", "LOCKED"]}
    }

    defp guards(fixture) do
      "objects/#{fixture}"
      |> analyze(@index)
      |> function("with_everything")
      |> Map.fetch!(:required_args)
      |> Map.new(&{&1.name, &1.guard})
    end

    test "each required argument is narrowed by its type" do
      assert guards("guarded-args") == %{
               "name" => {:call, "is_binary"},
               "count" => {:call, "is_integer"},
               "expand" => {:call, "is_boolean"},
               "config" => {:call, "is_binary"},
               "args" => {:call, "is_list"},
               "source" => {:struct, "Dagger.Directory"},
               "object" => {:call, "is_struct"},
               "sharing" => {:in, [":SHARED", ":PRIVATE", ":LOCKED"]},
               "at" => {:is_struct, "DateTime"}
             }
    end

    test "optional arguments are not guarded — there is no head to guard" do
      fun = function(analyze("objects/guarded-args", @index), "with_everything")

      assert [%{name: "owner", guard: nil}] = fun.optional_args
    end

    test "an enum falls back to is_atom when its members are unknown" do
      fun = function(analyze("objects/guarded-args"), "with_everything")
      sharing = Enum.find(fun.required_args, &(&1.name == "sharing"))

      assert sharing.guard == {:call, "is_atom"}
    end
  end

  test "enum members keep every value but are named the Elixir way" do
    mod = analyze("enums/render-enum")

    assert mod.kind == :enum
    assert Enum.map(mod.enum_values, & &1.name) == ["shared", "private", "locked"]
    assert Enum.map(mod.enum_values, & &1.value) == ["SHARED", "PRIVATE", "LOCKED"]
  end

  test "input fields become typed struct fields" do
    mod = analyze("inputs/build-arg")

    assert mod.kind == :input
    assert [%{name: "name", type: :string}, %{name: "value", type: :string}] = mod.fields
  end
end

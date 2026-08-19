defmodule Dagger.Codegen.TypeTest do
  use ExUnit.Case, async: true

  alias Dagger.Codegen.Type
  alias Dagger.Codegen.Introspection.Types.TypeRef

  defp ref(kind, name, of_type \\ nil),
    do: %TypeRef{kind: kind, name: name, of_type: of_type}

  defp non_null(inner), do: ref("NON_NULL", nil, inner)
  defp list(inner), do: ref("LIST", nil, inner)
  defp scalar(name), do: ref("SCALAR", name)
  defp object(name), do: ref("OBJECT", name)

  describe "normalize/2" do
    test "peels NON_NULL and makes nullability explicit" do
      assert Type.normalize(non_null(scalar("String"))) == :string
      assert Type.normalize(scalar("String")) == {:nullable, :string}
    end

    test "maps the built-in scalars onto Elixir types" do
      for {name, expected} <- [
            {"String", :string},
            {"Int", :int},
            {"Float", :float},
            {"Boolean", :boolean},
            {"DateTime", :datetime},
            {"Void", :void},
            {"ID", :id}
          ] do
        assert Type.normalize(non_null(scalar(name))) == expected
      end
    end

    test "keeps custom scalars as themselves" do
      assert Type.normalize(non_null(scalar("JSON"))) == {:scalar, "JSON"}
      assert Type.normalize(non_null(scalar("ContainerID"))) == {:scalar, "ContainerID"}
    end

    test "carries kinds through" do
      assert Type.normalize(non_null(object("Container"))) == {:object, "Container"}
      assert Type.normalize(non_null(ref("INTERFACE", "Node"))) == {:interface, "Node"}

      assert Type.normalize(non_null(ref("ENUM", "CacheSharingMode"))) ==
               {:enum, "CacheSharingMode"}

      assert Type.normalize(non_null(ref("INPUT_OBJECT", "BuildArg"))) == {:input, "BuildArg"}
    end

    test "nests lists, keeping element nullability" do
      assert Type.normalize(non_null(list(non_null(scalar("String"))))) == {:list, :string}
      assert Type.normalize(list(non_null(scalar("String")))) == {:nullable, {:list, :string}}

      assert Type.normalize(non_null(list(scalar("String")))) ==
               {:list, {:nullable, :string}}
    end

    test "an ID argument becomes the type its @expectedType names" do
      assert Type.normalize(non_null(scalar("ID")), {:object, "Directory"}) ==
               {:object, "Directory"}

      assert Type.normalize(non_null(scalar("ID")), {:interface, "Node"}) == {:interface, "Node"}
    end

    test "@expectedType reaches into lists" do
      assert Type.normalize(non_null(list(non_null(scalar("ID")))), {:object, "Container"}) ==
               {:list, {:object, "Container"}}
    end

    test "@expectedType does not apply to anything but ID" do
      assert Type.normalize(non_null(scalar("String")), {:object, "Directory"}) == :string
    end
  end

  describe "spec/1" do
    test "renders builtins" do
      assert Type.spec(:string) == "String.t()"
      assert Type.spec(:int) == "integer()"
      assert Type.spec(:float) == "float()"
      assert Type.spec(:boolean) == "boolean()"
      assert Type.spec(:datetime) == "DateTime.t()"
      assert Type.spec(:id) == "String.t()"
    end

    test "renders module-backed types" do
      assert Type.spec({:object, "EnvVariable"}) == "Dagger.EnvVariable.t()"
      assert Type.spec({:enum, "CacheSharingMode"}) == "Dagger.CacheSharingMode.t()"
      assert Type.spec({:scalar, "JSON"}) == "Dagger.JSON.t()"
    end

    test "renders nullability" do
      assert Type.spec({:nullable, {:object, "EnvVariable"}}) == "Dagger.EnvVariable.t() | nil"
    end

    test "renders lists" do
      assert Type.spec({:list, {:object, "EnvVariable"}}) == "[Dagger.EnvVariable.t()]"
      assert Type.spec({:list, {:nullable, :string}}) == "[String.t() | nil]"
    end

    test "a nullable list is spelled the same as a list" do
      assert Type.spec({:nullable, {:list, :string}}) == "[String.t()]"
    end
  end

  describe "encoder/1" do
    test "objects and interfaces travel as ids" do
      assert Type.encoder({:object, "Directory"}) == {:call, "Dagger.ID.id!"}
      assert Type.encoder({:interface, "Node"}) == {:call, "Dagger.ID.id!"}
      assert Type.encoder({:nullable, {:object, "Directory"}}) == {:call, "Dagger.ID.id!"}
      assert Type.encoder({:list, {:object, "Container"}}) == {:map, "Dagger.ID.id!"}
    end

    test "everything else goes as-is" do
      assert Type.encoder(:string) == :identity
      assert Type.encoder({:enum, "CacheSharingMode"}) == :identity
      assert Type.encoder({:list, :string}) == :identity
      assert Type.encoder({:input, "BuildArg"}) == :identity
    end
  end

  describe "guard/1" do
    test "scalars are guarded by their Elixir representation" do
      assert Type.guard(:string) == {:call, "is_binary"}
      assert Type.guard(:id) == {:call, "is_binary"}
      assert Type.guard({:scalar, "JSON"}) == {:call, "is_binary"}
      assert Type.guard(:int) == {:call, "is_integer"}
      assert Type.guard(:boolean) == {:call, "is_boolean"}
      assert Type.guard(:datetime) == {:is_struct, "DateTime"}
    end

    test "Float accepts an integer literal, so is_number and not is_float" do
      assert Type.guard(:float) == {:call, "is_number"}
    end

    test "objects and inputs are matched, not guarded" do
      assert Type.guard({:object, "Directory"}) == {:struct, "Dagger.Directory"}
      assert Type.guard({:input, "BuildArg"}) == {:struct, "Dagger.BuildArg"}
    end

    test "an interface has no struct of its own" do
      assert Type.guard({:interface, "Node"}) == {:call, "is_struct"}
    end

    test "lists are guarded by shape only" do
      assert Type.guard({:list, {:object, "Container"}}) == {:call, "is_list"}
    end

    test "enums are left to the analyzer, which knows their members" do
      assert Type.guard({:enum, "CacheSharingMode"}) == :enum
    end

    test "nothing useful can be said about a nullable or void type" do
      assert Type.guard({:nullable, :string}) == nil
      assert Type.guard(:void) == nil
    end
  end

  describe "non_null/1" do
    test "drops an outer nullable" do
      assert Type.non_null({:nullable, :string}) == :string
      assert Type.non_null(:string) == :string
      assert Type.nullable?({:nullable, :string})
      refute Type.nullable?(:string)
    end
  end

  describe "module/1" do
    test "unwraps to the backing module" do
      assert Type.module({:nullable, {:list, {:object, "Port"}}}) == "Dagger.Port"
      assert Type.module(:string) == nil
    end
  end

  describe "element/1" do
    test "returns the element type of a list, without its nullability" do
      assert Type.element({:list, {:object, "Port"}}) == {:object, "Port"}
      assert Type.element({:nullable, {:list, {:nullable, :string}}}) == :string
      assert Type.element(:string) == nil
    end
  end
end

defmodule Dagger.Codegen do
  @moduledoc """
  Generates the Dagger API bindings from a GraphQL introspection schema.
  """

  alias Dagger.Codegen.ElixirGenerator
  alias Dagger.Codegen.Introspection.Types.Schema

  @doc """
  Generate a module per schema type and write them into `outdir`.
  """
  def generate_to!(%Schema{} = schema, outdir) do
    File.mkdir_p!(outdir)
    index = index(schema)

    schema
    |> types()
    |> Task.async_stream(&write!(&1, index, outdir), ordered: false, timeout: :infinity)
    |> Stream.run()
  end

  @doc """
  Types the generator emits a module for, in the order it emits them.
  """
  def types(%Schema{types: types}) do
    types
    |> Enum.reject(&introspection_type?/1)
    |> Enum.map(&sort_fields/1)
  end

  @doc """
  What the generator needs to know about the rest of the schema while rendering
  one type: every type's kind, and every enum's members.
  """
  def index(%Schema{types: types}) do
    Map.new(types, fn type ->
      {type.name, %{kind: kind(type), enum_values: Enum.map(type.enum_values, & &1.name)}}
    end)
  end

  defp write!(type, index, outdir) do
    File.write!(
      Path.join(outdir, ElixirGenerator.filename(type)),
      ElixirGenerator.generate(type, index)
    )
  end

  defp kind(%{kind: "OBJECT"}), do: :object
  defp kind(%{kind: "INTERFACE"}), do: :interface
  defp kind(%{kind: "ENUM"}), do: :enum
  defp kind(%{kind: "INPUT_OBJECT"}), do: :input
  defp kind(%{kind: "SCALAR"}), do: :scalar
  defp kind(_type), do: :unknown

  # Introspection's own types, plus the scalars that map onto Elixir builtins.
  defp introspection_type?(type) do
    String.starts_with?(type.name, "_") or
      type.name in ["String", "Float", "Int", "Boolean", "DateTime", "ID"]
  end

  # Generated modules read better with their functions in alphabetical order.
  defp sort_fields(type) do
    %{
      type
      | fields: Enum.sort_by(type.fields, & &1.name),
        input_fields: Enum.sort_by(type.input_fields, & &1.name)
    }
  end
end

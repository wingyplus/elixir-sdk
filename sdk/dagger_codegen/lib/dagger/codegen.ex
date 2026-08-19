defmodule Dagger.Codegen do
  @moduledoc """
  Generates the Dagger API bindings from a GraphQL introspection schema.

  One schema type becomes one Elixir module: the analyzer decides what the module
  contains, the renderer prints it, and the formatter lays it out.
  """

  alias Dagger.Codegen.Analyzer
  alias Dagger.Codegen.Naming
  alias Dagger.Codegen.Render
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
  Generate the source for one type.

  `index` describes the rest of the schema; see `Analyzer.analyze/2`.
  """
  def generate(type, index \\ %{}) do
    type
    |> Analyzer.analyze(index)
    |> Render.render()
    |> format()
  end

  @doc """
  File the generated module belongs in.
  """
  def filename(type), do: Naming.var(type.name) <> ".ex"

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

  # Renderers emit unindented source and let the formatter lay it out, so this is
  # not optional polish — it is what makes the output readable. The trailing
  # newline matters too: without it every file fails `mix format --check-formatted`.
  defp format(code) do
    code
    |> IO.iodata_to_binary()
    |> Code.format_string!()
    |> then(&[&1, ?\n])
    |> IO.iodata_to_binary()
  end

  defp write!(type, index, outdir) do
    File.write!(Path.join(outdir, filename(type)), generate(type, index))
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

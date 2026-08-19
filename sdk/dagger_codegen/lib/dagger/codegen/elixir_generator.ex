defmodule Dagger.Codegen.ElixirGenerator do
  @moduledoc """
  Generates the Elixir bindings for one introspection type.
  """

  alias Dagger.Codegen.ElixirGenerator.Analyzer
  alias Dagger.Codegen.ElixirGenerator.Naming
  alias Dagger.Codegen.ElixirGenerator.Render

  @doc """
  Generate the source for `type`.

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
  Format generated source.

  Renderers emit unindented source and let the formatter lay it out, so this is
  not optional polish — it is what makes the output valid to read.
  """
  def format(code) do
    code
    |> IO.iodata_to_binary()
    |> Code.format_string!()
    |> then(&[&1, ?\n])
    |> IO.iodata_to_binary()
  end
end

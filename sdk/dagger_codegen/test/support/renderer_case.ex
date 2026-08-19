defmodule Dagger.Codegen.RendererCase do
  use ExUnit.CaseTemplate

  alias Dagger.Codegen.ElixirGenerator
  alias Dagger.Codegen.Introspection.Types.Type

  using do
    quote do
      use Mneme
      import Dagger.Codegen.RendererCase, only: [render_type: 1, render_type: 2, load_type: 1]
    end
  end

  @doc """
  Generate the module for the introspection type stored at `path`.

  `kinds` is the schema-wide type-kind map; fixtures only need to pass it when
  an `@expectedType` directive names an interface.

  Every rendering is checked for format-idempotence on the way through, so the
  snapshots below double as proof that generated output is `mix format` clean.
  """
  def render_type(path, kinds \\ %{}) do
    code = path |> load_type() |> ElixirGenerator.generate(kinds)

    formatted = IO.iodata_to_binary([Code.format_string!(code), ?\n])

    if formatted != code do
      raise """
      generated code is not format-idempotent for #{path}.

      #{diff_hint(code, formatted)}
      """
    end

    String.trim_trailing(code, "\n")
  end

  @doc """
  Decode a single introspection type from a fixture file.
  """
  def load_type(path) do
    path |> File.read!() |> JSON.decode!() |> Type.from_map()
  end

  defp diff_hint(code, formatted) do
    generated = String.split(code, "\n")
    expected = String.split(formatted, "\n")

    Enum.zip(generated, expected)
    |> Enum.with_index(1)
    |> Enum.find_value("output lengths differ", fn {{got, want}, line} ->
      got != want and "line #{line}:\n  generated: #{inspect(got)}\n  formatted: #{inspect(want)}"
    end)
  end
end

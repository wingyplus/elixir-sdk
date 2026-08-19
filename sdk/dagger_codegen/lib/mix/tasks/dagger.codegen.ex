defmodule Mix.Tasks.Dagger.Codegen do
  @shortdoc "Generate Dagger API from introspection.json"

  @moduledoc @shortdoc

  use Mix.Task

  alias Dagger.Codegen.Introspection.Types.Schema

  @impl true
  def run(args) do
    :argparse.run(Enum.map(args, &String.to_charlist/1), cli(), %{progname: :dagger_codegen})
  end

  defp cli() do
    %{
      commands: %{
        ~c"generate" => %{
          arguments: [
            %{name: :outdir, type: :binary, long: ~c"-outdir", required: true},
            %{name: :introspection, type: :binary, long: ~c"-introspection", required: true}
          ],
          handler: &handle_generate/1
        }
      }
    }
  end

  defp handle_generate(%{outdir: outdir, introspection: introspection}) do
    %{"__schema" => schema} = introspection |> File.read!() |> JSON.decode!()

    Mix.shell().info("Generate code to #{outdir}")

    schema
    |> Schema.from_map()
    |> Dagger.Codegen.generate_to!(outdir)
  end
end

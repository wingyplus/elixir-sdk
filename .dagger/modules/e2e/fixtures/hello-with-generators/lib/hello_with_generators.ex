defmodule HelloWithGenerators do
  @moduledoc false

  use Dagger.Mod.Object, name: "HelloWithGenerators"

  # A `:generate` function must return the core Changeset type and be callable
  # with no arguments -- see `validateGeneratorFunction` in the engine.
  #
  # Run as a check, a generator PASSES only when its changeset is empty. A
  # non-empty changeset means the generated output is stale.
  defn up_to_date_generator() :: Dagger.Changeset.t(), :generate do
    dir =
      dag()
      |> Dagger.Client.directory()
      |> Dagger.Directory.with_new_file("a.txt", "a\n")

    Dagger.Directory.changes(dir, dir)
  end

  # Always produces changes, so it always fails when run as a check.
  defn stale_generator() :: Dagger.Changeset.t(), :generate do
    before = dag() |> Dagger.Client.directory()

    before
    |> Dagger.Directory.with_new_file("generated.txt", "hello from a generator\n")
    |> Dagger.Directory.changes(before)
  end

  # Declared with both options. The engine deduplicates it to a single *check*,
  # so it runs via RunCheck rather than RunGeneratorAsCheck and is NOT failed
  # for producing changes -- even though it produces the same changes as
  # stale_generator above. Verified against 1.0.0-beta.9: this reports OK while
  # stale_generator reports ERROR.
  defn generator_and_check() :: Dagger.Changeset.t(), [:check, :generate] do
    before = dag() |> Dagger.Client.directory()

    before
    |> Dagger.Directory.with_new_file("both.txt", "hello again\n")
    |> Dagger.Directory.changes(before)
  end

  # Neither a check nor a generator: must not be discovered by `dagger check`.
  defn plain_function() :: String.t() do
    "not a check"
  end
end

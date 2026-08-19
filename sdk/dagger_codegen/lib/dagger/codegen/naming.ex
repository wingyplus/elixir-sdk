defmodule Dagger.Codegen.Naming do
  @moduledoc """
  Maps GraphQL names onto Elixir names.

  The GraphQL root type is called `Query`; the SDK exposes it as `Dagger.Client`,
  which is why every function here special-cases that one name.
  """

  @doc """
  Module name for a GraphQL type, e.g. `"CacheVolume"` -> `"Dagger.CacheVolume"`.
  """
  def module("Query"), do: module("Client")
  def module(name), do: "Dagger." <> Macro.camelize(name)

  @doc """
  Variable (and file) name for a GraphQL type, e.g. `"CacheVolume"` -> `"cache_volume"`.
  """
  def var("Query"), do: var("Client")
  def var(name), do: Macro.underscore(name)

  @doc """
  Function name for a GraphQL field, e.g. `"withEnvVariable"` -> `"with_env_variable"`.
  """
  def function(name) do
    name
    |> normalize_acronym()
    |> escape_reserved()
    |> Macro.underscore()
    |> predicate()
  end

  # Elixir spells predicates `foo?`, not `is_foo` — the latter is reserved for guards.
  defp predicate("is_" <> rest), do: rest <> "?"
  defp predicate(name), do: name

  @reserved_words ~w(
    true false nil when and or not in fn do end catch rescue after else
  )

  defp escape_reserved(name) when name in @reserved_words, do: name <> "_"
  defp escape_reserved(name), do: name

  # `Macro.underscore/1` turns runs of capitals into one word, so `GPU` would
  # become `gpu` glued to whatever follows. See dagger/dagger#6310.
  @acronyms %{"GPU" => "Gpu", "VCS" => "Vcs"}

  defp normalize_acronym(name) do
    Enum.reduce(@acronyms, name, fn {acronym, replacement}, name ->
      String.replace(name, acronym, replacement)
    end)
  end

  @doc """
  Rewrite API references in documentation to their Elixir spelling, so a doc
  that mentions `withExec` points at the function the reader can actually call.
  """
  def doc(doc) do
    for [text, api] <- Regex.scan(~r/`(?<name>[a-zA-Z0-9]+)`/, doc), reduce: doc do
      acc -> String.replace(acc, text, "`#{function(api)}`")
    end
  end
end

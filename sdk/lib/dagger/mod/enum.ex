defmodule Dagger.Mod.Enum do
  @moduledoc """
  Write a Dagger module enum in Elixir.

  An enum is a type that only accepts one value from a fixed list, such as a
  severity level or a log format.

  ## Declare an enum

  Add `use Dagger.Mod.Enum` to a module, give the enum a name and list its
  members in `:values`:

      defmodule Severity do
        @moduledoc \"""
        A severity level.
        \"""

        use Dagger.Mod.Enum, name: "Severity", values: [:low, :medium, :high]
      end

  The `@moduledoc` becomes the enum description shown to users.

  ## Use an enum

  An enum can be used as an argument or a return type of a function declared
  with `Dagger.Mod.Object`, by its `t()` type:

      defmodule Scanner do
        use Dagger.Mod.Object, name: "Scanner"

        defn scan(severity: Severity.t()) :: String.t() do
          case severity do
            :low -> "only report low issues"
            :medium -> "only report medium issues"
            :high -> "only report high issues"
          end
        end
      end

  Each member is an atom in Elixir, so the function receives `:low`,
  `:medium` or `:high`, and returns an enum by returning one of them. From the
  command line, a member is given by name:

      dagger call scan --severity=high

  The module also defines a function for each member, which returns it:

      Severity.high()
      #=> :high

  ## Member options

  A member can carry options by writing it as a keyword:

      use Dagger.Mod.Enum,
        name: "Severity",
        values: [
          :low,
          medium: [doc: "Medium severity."],
          high: [doc: "High severity.", deprecated: "Use `critical` instead."],
          critical: [doc: "Critical severity."]
        ]

  | Option        | Description                                       |
  | ------------- | ------------------------------------------------- |
  | `:doc`        | The member description.                           |
  | `:deprecated` | Mark the member as deprecated, with a reason.     |

  ## Member values

  By default, a member's value is its name. To give a member a different
  value, write the value as a string, with or without options:

      use Dagger.Mod.Enum,
        name: "Severity",
        values: [
          low: "LOW",
          high: {"HIGH", doc: "High severity."}
        ]

  The member is still `:low` or `:high` in Elixir and on the command line.
  The value is what other Dagger modules see when they use this enum.
  """

  defmacro __using__(opts) do
    values = opts[:values]
    name = opts[:name]

    if is_nil(values) do
      raise "The option `:values` need to be set."
    end

    functions = Enum.map(values, &defenum/1)

    atoms = Enum.map_join(values, "|", &(&1 |> key() |> Macro.to_string()))

    {:ok, ast_type} = Code.string_to_quoted("@type t() :: #{atoms}")

    quote do
      use Dagger.Core.Base, kind: :enum, name: unquote(name)

      unquote(ast_type)

      def __enum__(:name), do: unquote(name)
      def __enum__(:keys), do: unquote(values)

      unquote_splicing(functions)
    end
  end

  defp defenum(member) do
    key = key(member)
    value = value(member)
    doc = doc(member)
    deprecated = deprecated(member)
    name = Atom.to_string(key)
    fname = name |> String.downcase() |> String.to_atom()

    quote do
      def __enum__(:value, unquote(key)), do: unquote(value)
      def __enum__(:key, unquote(name)), do: unquote(key)
      def __enum__(:doc, unquote(key)), do: unquote(doc)
      def __enum__(:deprecated, unquote(key)), do: unquote(deprecated)

      def unquote(fname)(), do: unquote(key)
      def from_string(unquote(name)), do: unquote(key)
    end
  end

  defp key(key) when is_atom(key), do: key
  defp key({key, _}) when is_atom(key), do: key

  # A member that declares no value of its own takes its key as its value, which
  # is what the engine would default it to anyway.
  defp value(key) when is_atom(key), do: Atom.to_string(key)
  defp value({key, options}) when is_list(options), do: Atom.to_string(key)
  defp value({_key, value}) when is_binary(value), do: value
  defp value({_key, {value, options}}) when is_binary(value) and is_list(options), do: value

  defp doc(key) when is_atom(key), do: nil
  defp doc({_key, options}) when is_list(options), do: options[:doc]
  defp doc({_key, value}) when is_binary(value), do: nil
  defp doc({_key, {value, options}}) when is_binary(value) and is_list(options), do: options[:doc]

  defp deprecated(key) when is_atom(key), do: nil
  defp deprecated({_key, options}) when is_list(options), do: options[:deprecated]
  defp deprecated({_key, value}) when is_binary(value), do: nil

  defp deprecated({_key, {value, options}}) when is_binary(value) and is_list(options),
    do: options[:deprecated]

  @doc """
  The member keys of the enum `module`, in declaration order.

  Works for both enums declared with this module and enums that come from
  codegen, which carry their members in their `t()` typespec instead.
  """
  def keys(module) do
    if custom_enum?(module) do
      module.__enum__(:keys) |> Enum.map(&key/1)
    else
      extract_keys_from_base(module)
    end
  end

  @doc """
  The wire value the member `key` declares, falling back to the key itself.
  """
  def get_key_value(module, key) do
    if custom_enum?(module) do
      module.__enum__(:value, key)
    else
      Atom.to_string(key)
    end
  end

  @doc """
  The doc string attached to the member `key`, if any.
  """
  def get_key_description(module, key) do
    if custom_enum?(module) do
      module.__enum__(:doc, key)
    else
      nil
    end
  end

  @doc """
  The deprecation reason attached to the member `key`, if any.
  """
  def get_key_deprecated(module, key) do
    if custom_enum?(module) do
      module.__enum__(:deprecated, key)
    else
      nil
    end
  end

  defp extract_keys_from_base(module) do
    {:ok, [type: {:t, {:type, _, :union, unions}, _}]} = Code.Typespec.fetch_types(module)
    unions |> Enum.map(&elem(&1, 2))
  end

  # An enum from codegen has no `__enum__/2`: its members name themselves and
  # carry no docs.
  defp custom_enum?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__enum__, 2)
  end
end

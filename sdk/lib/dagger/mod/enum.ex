defmodule Dagger.Mod.Enum do
  @moduledoc """
  Declare a module as an enum type.

  A member is spelled `key`, `key: [doc: ...]`, `key: value` or
  `key: {value, doc: ...}`. The key is the member's identity: it is the atom the
  Elixir side works with, the name the engine registers the member under, and
  the string the engine hands back when the member is passed to a function. The
  value is the wire value the member declares - what a dependent SDK generates
  its constant from - and defaults to the key.
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
    name = Atom.to_string(key)
    fname = name |> String.downcase() |> String.to_atom()

    quote do
      def __enum__(:value, unquote(key)), do: unquote(value)
      def __enum__(:key, unquote(name)), do: unquote(key)
      def __enum__(:doc, unquote(key)), do: unquote(doc)

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

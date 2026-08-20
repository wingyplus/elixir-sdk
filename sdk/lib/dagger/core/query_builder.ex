defmodule Dagger.Core.QueryBuilder do
  @moduledoc false

  @type t :: %__MODULE__{
          name: String.t() | nil,
          args: map() | nil,
          prev: t() | nil,
          alias: String.t()
        }

  defstruct [:name, :args, :prev, alias: ""]

  def query(), do: %__MODULE__{}

  def select(%__MODULE__{} = selection, name) when is_binary(name) do
    select_with_alias(selection, "", name)
  end

  def select_with_alias(%__MODULE__{} = selection, alias, name)
      when is_binary(alias) and is_binary(name) do
    %__MODULE__{
      name: name,
      alias: alias,
      prev: selection
    }
  end

  def inline_fragment(%__MODULE__{} = selection, type_name) when is_binary(type_name) do
    %__MODULE__{
      name: "... on #{type_name}",
      prev: selection
    }
  end

  def put_arg(%__MODULE__{args: args} = selection, name, value) when is_binary(name) do
    args = args || %{}

    %{selection | args: Map.put(args, name, value)}
  end

  def maybe_put_arg(%__MODULE__{} = selection, _name, nil), do: selection

  def maybe_put_arg(%__MODULE__{} = selection, name, value) do
    put_arg(selection, name, value)
  end

  def build(%__MODULE__{} = selection) do
    # The whole query is assembled as iodata and copied into a binary once, at
    # the end: a selection that carries a large argument, a file's contents say,
    # is otherwise copied again for every enclosing selection.
    {fields, depth} = build_fields(selection, [], 0)

    IO.iodata_to_binary([Enum.intersperse(fields, ?{), :binary.copy("}", depth)])
  end

  defp build_fields(%__MODULE__{prev: nil}, acc, depth) do
    {["query" | acc], depth}
  end

  defp build_fields(
         %__MODULE__{prev: selection, name: name, args: args, alias: alias},
         acc,
         depth
       ) do
    build_fields(selection, [[build_alias(alias), name | build_args(args)] | acc], depth + 1)
  end

  defp build_alias(""), do: []
  defp build_alias(alias), do: [alias, ~c":"]

  defp build_args(nil), do: []

  defp build_args(args) do
    fun = fn {name, value} -> [name, ~c":", encode_value(value)] end
    [~c"(", Enum.map_intersperse(args, ",", fun), ~c")"]
  end

  # `null` only shows up when an argument is explicitly set to it:
  # `maybe_put_arg/3` drops the argument instead.
  defp encode_value(nil), do: ~c"null"

  defp encode_value(value) when is_atom(value),
    do: to_string(value)

  defp encode_value(value) when is_binary(value) do
    [~c"\"", escape(value), ~c"\""]
  end

  defp encode_value(value) when is_list(value) do
    [~c"[", Enum.map_intersperse(value, ",", &encode_value/1), ~c"]"]
  end

  defp encode_value(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> encode_value()
  end

  defp encode_value(value) when is_map(value) do
    # Input objects come in as structs whose keys are the snake case names the
    # SDK exposes, so they have to be turned back into the schema's camel case
    # ones. A field left as `nil` is an absent field, not a null one, and the
    # fields are sorted because a map does not iterate in a stable order.
    fun = fn {name, value} -> [camelize(name), ~c":", encode_value(value)] end

    fields =
      value
      |> Enum.reject(fn {_name, value} -> is_nil(value) end)
      |> Enum.sort()
      |> Enum.map_intersperse(",", fun)

    [~c"{", fields, ~c"}"]
  end

  defp encode_value(value), do: [to_string(value)]

  defp camelize(name) do
    case :binary.split(to_string(name), "_", [:global]) do
      [name] -> name
      [first | rest] -> [first | Enum.map(rest, &capitalize/1)]
    end
  end

  defp capitalize(<<first, rest::binary>>) when first in ?a..?z, do: [first - 32 | rest]
  defp capitalize(part), do: part

  # The bytes that cannot appear literally inside a GraphQL string: the seven
  # with a short escape, and the remaining control characters, which are written
  # as `\uXXXX`.
  @short_escapes %{
    ?" => ~S(\"),
    ?\\ => ~S(\\),
    ?\b => ~S(\b),
    ?\f => ~S(\f),
    ?\n => ~S(\n),
    ?\r => ~S(\r),
    ?\t => ~S(\t)
  }

  @escapable for(char <- 0x00..0x1F, do: <<char>>) ++ [~s("), "\\"]

  # Nothing needs escaping most of the time, and an argument can be large - the
  # contents of a file, say - so the string is first scanned for anything that
  # does, which `:binary.match/2` does in one pass over the whole binary instead
  # of a byte at a time. Only a string that does need it walks the clauses
  # below, and even then the runs between escapes are copied whole, appended to
  # a binary the VM grows in place rather than to a list the query is later
  # flattened from.
  defp escape(string) do
    case :binary.match(string, escape_pattern()) do
      :nomatch -> string
      _ -> escape(string, string, 0, 0, <<>>)
    end
  end

  # A compiled pattern is a reference, so it cannot be a module attribute; it is
  # built on first use and kept for the lifetime of the VM instead.
  defp escape_pattern() do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        pattern = :binary.compile_pattern(@escapable)
        :persistent_term.put(__MODULE__, pattern)
        pattern

      pattern ->
        pattern
    end
  end

  defp escape(<<>>, original, from, len, acc) do
    <<acc::binary, binary_part(original, from, len)::binary>>
  end

  for {char, escaped} <- @short_escapes do
    defp escape(<<unquote(char), rest::binary>>, original, from, len, acc) do
      escape(rest, original, from + len + 1, 0, <<
        acc::binary,
        binary_part(original, from, len)::binary,
        unquote(escaped)
      >>)
    end
  end

  defp escape(<<char, rest::binary>>, original, from, len, acc) when char < 0x20 do
    escape(rest, original, from + len + 1, 0, <<
      acc::binary,
      binary_part(original, from, len)::binary,
      unicode_escape(char)::binary
    >>)
  end

  defp escape(<<_char, rest::binary>>, original, from, len, acc) do
    escape(rest, original, from, len + 1, acc)
  end

  for char <- 0x00..0x1F do
    defp unicode_escape(unquote(char)), do: unquote("\\u00" <> Base.encode16(<<char>>))
  end

  def path(selection) do
    path(selection, [])
  end

  def path(%__MODULE__{prev: nil, name: nil}, acc), do: acc

  def path(%__MODULE__{prev: selection, name: "... on " <> _}, acc),
    do: path(selection, acc)

  def path(%__MODULE__{prev: selection, name: name}, acc), do: path(selection, [name | acc])
end

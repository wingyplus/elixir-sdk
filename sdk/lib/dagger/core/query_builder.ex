defmodule Dagger.Core.QueryBuilder do
  @moduledoc false

  @typedoc """
  A field inside a leaf field set: a name, or a name and the fields to select
  below it.
  """
  @type field :: String.t() | {String.t(), [field()]}

  @typedoc """
  A single field name, or the set of leaf fields a query ends with.
  """
  @type name :: String.t() | [field()]

  @typedoc """
  Arguments to a field, keyed by the schema's own names.
  """
  @type args :: [{atom() | String.t(), term()}]

  @type t :: %__MODULE__{
          name: name() | nil,
          args: args(),
          prev: t() | nil
        }

  defstruct [:name, :prev, args: []]

  def query(), do: %__MODULE__{}

  @doc """
  Select `name`, optionally with `args`.

  An argument whose value is `nil` is left out of the query entirely, which is
  what an unset optional argument means. To send a literal `null`, nest it: a
  `nil` inside a list or an input object is encoded as one.
  """
  def select(%__MODULE__{} = selection, name, args \\ [])
      when is_binary(name) and is_list(args) do
    %__MODULE__{
      name: name,
      args: reject_unset(args),
      prev: selectable!(selection)
    }
  end

  @doc """
  Select a set of leaf fields, `envVariables { id name value }` say.

  A field that is not itself a leaf carries the fields to select below it as
  `{name, fields}`, nested as deeply as the schema needs:

      select_fields(selection, ["a", "b", {"c", ["d"]}])
      #=> a b c{d}

  This is where a query ends: a node holding more than one field has no single
  field for a further selection to hang from, so `select/3`, `select_fields/2`
  and `inline_fragment/2` all refuse to extend one - the nesting a set needs is
  written into the set itself. The response for the selection *above* it is what
  `Dagger.Core.Client.execute/2` returns - a map of the fields, or a list of such
  maps - so a leaf set contributes nothing to `path/1`.
  """
  def select_fields(%__MODULE__{} = selection, [_ | _] = names) do
    %__MODULE__{
      name: Enum.map(names, &valid_field!/1),
      prev: selectable!(selection)
    }
  end

  # A malformed field is worth catching here, where the caller wrote it, rather
  # than in `build/1`: an unnamed field or an empty nested set is not a query the
  # engine can parse, and a bad element would otherwise surface as a
  # FunctionClauseError a long way from where it came from.
  defp valid_field!(name) when is_binary(name), do: name

  defp valid_field!({name, [_ | _] = nested}) when is_binary(name),
    do: {name, Enum.map(nested, &valid_field!/1)}

  defp valid_field!(field) do
    raise ArgumentError,
          "expected a field name or a {name, fields} pair with at least one field, " <>
            "got: #{inspect(field)}"
  end

  def inline_fragment(%__MODULE__{} = selection, type_name) when is_binary(type_name) do
    %__MODULE__{
      name: "... on #{type_name}",
      prev: selectable!(selection)
    }
  end

  defp selectable!(%__MODULE__{name: name} = selection) when not is_list(name), do: selection

  defp selectable!(%__MODULE__{name: names}) do
    raise ArgumentError,
          "cannot select below the leaf fields #{inspect(names)}: a query ends there"
  end

  defp reject_unset(args), do: Enum.reject(args, fn {_name, value} -> is_nil(value) end)

  def build(%__MODULE__{} = selection) do
    # The whole query is assembled as iodata and copied into a binary once, at
    # the end: a selection that carries a large argument, a file's contents say,
    # is otherwise copied again for every enclosing selection.
    #
    # The compiled escape pattern is looked up once here and carried down rather
    # than fetched inside `escape/2`, which runs once per string: the lookup
    # costs about a sixth of the scan it precedes, so a query encoding many
    # small strings - a list argument of a couple of hundred flags, say - was
    # paying for it far more often than it needed to.
    {fields, depth} = build_fields(selection, [], 0, escape_pattern())

    IO.iodata_to_binary([Enum.intersperse(fields, ?{), :binary.copy("}", depth)])
  end

  defp build_fields(%__MODULE__{prev: nil}, acc, depth, _pattern) do
    {["query" | acc], depth}
  end

  defp build_fields(%__MODULE__{prev: selection, name: name, args: args}, acc, depth, pattern) do
    build_fields(
      selection,
      [[build_name(name) | build_args(args, pattern)] | acc],
      depth + 1,
      pattern
    )
  end

  defp build_name(names) when is_list(names), do: build_field_set(names)
  defp build_name(name), do: name

  defp build_field_set(names), do: Enum.map_intersperse(names, ?\s, &build_field/1)

  defp build_field({name, nested}), do: [name, ?{, build_field_set(nested), ?}]
  defp build_field(name), do: name

  defp build_args([], _pattern), do: []

  defp build_args(args, pattern) do
    fun = fn {name, value} -> [arg_name(name), ?:, encode_value(value, pattern)] end
    [?(, Enum.map_intersperse(args, ?,, fun), ?)]
  end

  # Generated code names arguments with the schema's own camel case atoms; a
  # binary is accepted too, and costs nothing to write out.
  defp arg_name(name) when is_atom(name), do: Atom.to_string(name)
  defp arg_name(name), do: name

  # `null` is only reachable for a value nested inside a list or an input
  # object: `select/3` drops an argument that is `nil` rather than sending one.
  defp encode_value(nil, _pattern), do: "null"

  defp encode_value(value, _pattern) when is_atom(value),
    do: to_string(value)

  defp encode_value(value, pattern) when is_binary(value) do
    [?", escape(value, pattern), ?"]
  end

  defp encode_value(value, pattern) when is_list(value) do
    [?[, Enum.map_intersperse(value, ?,, &encode_value(&1, pattern)), ?]]
  end

  defp encode_value(value, pattern) when is_struct(value) do
    value
    |> Map.from_struct()
    |> encode_value(pattern)
  end

  defp encode_value(value, pattern) when is_map(value) do
    # Input objects come in as structs whose keys are the snake case names the
    # SDK exposes, so they have to be turned back into the schema's camel case
    # ones. A field left as `nil` is an absent field, not a null one, and the
    # fields are sorted because a map does not iterate in a stable order.
    fun = fn {name, value} -> [camelize(name), ?:, encode_value(value, pattern)] end

    fields =
      value
      |> Enum.reject(fn {_name, value} -> is_nil(value) end)
      |> Enum.sort()
      |> Enum.map_intersperse(?,, fun)

    [?{, fields, ?}]
  end

  defp encode_value(value, _pattern), do: [to_string(value)]

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
  # flattened from. `pattern` comes from `build/1`, which fetches it once.
  defp escape(string, pattern) do
    case :binary.match(string, pattern) do
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

  @doc """
  The names to follow through the response to reach what the query selected.

  Inline fragments are skipped - they do not appear in the response - and so is
  a trailing leaf field set, whose fields are the caller's to read.
  """
  def path(selection) do
    path(selection, [])
  end

  defp path(%__MODULE__{prev: nil, name: nil}, acc), do: acc

  defp path(%__MODULE__{prev: selection, name: "... on " <> _}, acc),
    do: path(selection, acc)

  defp path(%__MODULE__{prev: selection, name: names}, acc) when is_list(names),
    do: path(selection, acc)

  defp path(%__MODULE__{prev: selection, name: name}, acc), do: path(selection, [name | acc])
end

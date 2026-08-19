defmodule Dagger.Codegen.Type do
  @moduledoc """
  Canonical Elixir view of a GraphQL type reference.

  GraphQL hands us types in wire shape — a `NON_NULL`/`LIST` chain that has to be
  peeled to learn anything. `normalize/2` peels it exactly once, up front, so
  every consumer downstream is a flat pattern match instead of another walk.
  """

  alias Dagger.Codegen.Naming
  alias Dagger.Codegen.Introspection.Types.TypeRef

  @type name :: String.t()

  @type t ::
          :string
          | :int
          | :float
          | :boolean
          | :datetime
          | :id
          | :void
          | {:scalar, name()}
          | {:object, name()}
          | {:interface, name()}
          | {:enum, name()}
          | {:input, name()}
          | {:list, t()}
          | {:nullable, t()}

  @doc """
  Normalize a GraphQL type reference.

  Nullability is explicit: `NON_NULL` disappears and everything else is wrapped
  in `{:nullable, _}`.

  `expected` is the type named by an `@expectedType` directive, already resolved
  to a `t()` by the caller (only it knows whether the name is an object or an
  interface). It is what turns an `ID` argument into the type it identifies.
  """
  @spec normalize(TypeRef.t(), t() | nil) :: t()
  def normalize(type_ref, expected \\ nil)

  def normalize(%TypeRef{kind: "NON_NULL", of_type: inner}, expected),
    do: unwrapped(inner, expected)

  def normalize(%TypeRef{} = type_ref, expected), do: {:nullable, unwrapped(type_ref, expected)}

  defp unwrapped(%TypeRef{kind: "LIST", of_type: inner}, expected),
    do: {:list, normalize(inner, expected)}

  defp unwrapped(%TypeRef{kind: "SCALAR", name: name}, expected), do: scalar(name, expected)
  defp unwrapped(%TypeRef{kind: "OBJECT", name: name}, _expected), do: {:object, name}
  defp unwrapped(%TypeRef{kind: "INTERFACE", name: name}, _expected), do: {:interface, name}
  defp unwrapped(%TypeRef{kind: "ENUM", name: name}, _expected), do: {:enum, name}
  defp unwrapped(%TypeRef{kind: "INPUT_OBJECT", name: name}, _expected), do: {:input, name}

  defp scalar("String", _expected), do: :string
  defp scalar("Int", _expected), do: :int
  defp scalar("Float", _expected), do: :float
  defp scalar("Boolean", _expected), do: :boolean
  defp scalar("DateTime", _expected), do: :datetime
  defp scalar("Void", _expected), do: :void
  defp scalar("ID", nil), do: :id
  defp scalar("ID", expected), do: expected
  defp scalar(name, _expected), do: {:scalar, name}

  @doc """
  Render the type as a typespec.
  """
  @spec spec(t()) :: String.t()
  def spec({:nullable, {:list, _} = list}), do: spec(list)
  def spec({:nullable, inner}), do: spec(inner) <> " | nil"
  def spec({:list, inner}), do: "[" <> spec(inner) <> "]"
  def spec(:string), do: "String.t()"
  def spec(:int), do: "integer()"
  def spec(:float), do: "float()"
  def spec(:boolean), do: "boolean()"
  def spec(:datetime), do: "DateTime.t()"
  def spec(:id), do: "String.t()"
  def spec(:void), do: "Dagger.Void.t()"

  def spec({kind, name}) when kind in [:scalar, :object, :interface, :enum, :input],
    do: Naming.module(name) <> ".t()"

  @doc """
  Module backing the type, for struct construction. `nil` for types that have no
  module of their own.
  """
  @spec module(t()) :: String.t() | nil
  def module({:nullable, inner}), do: module(inner)
  def module({:list, inner}), do: module(inner)

  def module({kind, name}) when kind in [:scalar, :object, :interface, :enum, :input],
    do: Naming.module(name)

  def module(_type), do: nil

  @doc """
  How a value of this type is turned into something the GraphQL query can carry.

  Objects and interfaces travel as IDs; everything else goes as-is.
  """
  @spec encoder(t()) :: :identity | {:call, String.t()} | {:map, String.t()}
  def encoder({:nullable, inner}), do: encoder(inner)
  def encoder({:list, inner}), do: as_map(encoder(inner))
  def encoder({kind, _name}) when kind in [:object, :interface], do: {:call, "Dagger.ID.id!"}
  def encoder(_type), do: :identity

  defp as_map({:call, fun}), do: {:map, fun}
  defp as_map(_encoder), do: :identity

  @doc """
  How a required argument of this type is checked in the function head.

  Objects and inputs are matched structurally; everything else that can be
  guarded gets a guard. `:enum` is resolved by the analyzer, which is the only
  thing that knows the enum's members. `nil` means the type cannot be narrowed.
  """
  @spec guard(t()) ::
          {:call, String.t()} | {:is_struct, String.t()} | {:struct, String.t()} | :enum | nil
  def guard(:string), do: {:call, "is_binary"}
  def guard(:id), do: {:call, "is_binary"}
  def guard({:scalar, _name}), do: {:call, "is_binary"}
  def guard(:int), do: {:call, "is_integer"}
  # GraphQL's Float accepts an integer literal, so `is_float/1` would be wrong.
  def guard(:float), do: {:call, "is_number"}
  def guard(:boolean), do: {:call, "is_boolean"}
  def guard(:datetime), do: {:is_struct, "DateTime"}
  def guard({:list, _inner}), do: {:call, "is_list"}
  def guard({:enum, _name}), do: :enum
  def guard({:object, name}), do: {:struct, Naming.module(name)}
  def guard({:input, name}), do: {:struct, Naming.module(name)}
  # An interface has no struct of its own to match against.
  def guard({:interface, _name}), do: {:call, "is_struct"}
  def guard(_type), do: nil

  @doc """
  Drop an outer `{:nullable, _}`.

  Optional arguments are spelled without it: leaving a key out of the keyword
  list is how you say "absent", so `nil` is never a value worth accepting.
  """
  def non_null({:nullable, inner}), do: inner
  def non_null(type), do: type

  @doc "Whether a value of this type may be `nil`."
  def nullable?({:nullable, _inner}), do: true
  def nullable?(_type), do: false

  @doc "Whether the type carries no value."
  def void?(:void), do: true
  def void?({:nullable, inner}), do: void?(inner)
  def void?(_type), do: false

  @doc "Whether the type is an enum, or a list of them."
  def enum?({:enum, _name}), do: true
  def enum?({:nullable, inner}), do: enum?(inner)
  def enum?(_type), do: false

  @doc "Whether the type is an object or interface, or a list of them."
  def node?({kind, _name}) when kind in [:object, :interface], do: true
  def node?({:nullable, inner}), do: node?(inner)
  def node?(_type), do: false

  @doc "Element type of a list, or `nil` if the type is not a list."
  def element({:nullable, inner}), do: element(inner)
  def element({:list, inner}), do: non_null(inner)
  def element(_type), do: nil
end

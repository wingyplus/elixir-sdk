defmodule Dagger.Codegen.ElixirGenerator.Analyzer do
  @moduledoc """
  Turns an introspection type into the `ModuleDef` the renderer prints.

  Every decision that used to be re-made in three places — required vs optional,
  whether an argument travels as an id, what a field returns — is made once here.
  """

  alias Dagger.Codegen.ElixirGenerator.IR.Arg
  alias Dagger.Codegen.ElixirGenerator.IR.EnumValue
  alias Dagger.Codegen.ElixirGenerator.IR.Function
  alias Dagger.Codegen.ElixirGenerator.IR.ModuleDef
  alias Dagger.Codegen.ElixirGenerator.Naming
  alias Dagger.Codegen.ElixirGenerator.Type
  alias Dagger.Codegen.Introspection.Types.Directive
  alias Dagger.Codegen.Introspection.Types.InputValue

  @doc """
  Analyze one introspection type.

  `index` describes the rest of the schema, keyed by GraphQL type name:
  `%{"Node" => %{kind: :interface, enum_values: []}}`. Two things need it — an
  `@expectedType` directive names a type without saying whether it is an object
  or an interface (interfaces have no struct to match on), and an enum argument
  is guarded against its own members.
  """
  @spec analyze(struct(), %{String.t() => map()}) :: ModuleDef.t()
  def analyze(type, index \\ %{})

  def analyze(%{kind: kind} = type, index) when kind in ["OBJECT", "INTERFACE"] do
    %ModuleDef{
      base(type)
      | kind: if(kind == "INTERFACE", do: :interface, else: :object),
        derives: derives(type),
        functions: Enum.map(type.fields, &function(&1, type, index))
    }
  end

  def analyze(%{kind: "ENUM"} = type, _index) do
    %ModuleDef{base(type) | kind: :enum, enum_values: Enum.map(type.enum_values, &enum_value/1)}
  end

  def analyze(%{kind: "INPUT_OBJECT"} = type, index) do
    %ModuleDef{base(type) | kind: :input, fields: Enum.map(type.input_fields, &arg(&1, index))}
  end

  def analyze(%{kind: "SCALAR"} = type, _index) do
    %ModuleDef{base(type) | kind: :scalar}
  end

  defp base(type) do
    %ModuleDef{
      module: Naming.module(type.name),
      var: Naming.var(type.name),
      gql_name: type.name,
      # ExDoc drops a module with no @moduledoc, so fall back to its own name.
      moduledoc:
        if(blank?(type.description), do: Naming.module(type.name), else: type.description)
    }
  end

  @protocols [{"id", "Dagger.ID"}, {"sync", "Dagger.Sync"}]

  defp derives(type) do
    names = Enum.map(type.fields, & &1.name)

    for {field, protocol} <- @protocols, field in names, do: protocol
  end

  defp enum_value(value) do
    %EnumValue{name: Naming.function(value.name), value: value.name, doc: doc(value)}
  end

  ## Functions

  defp function(field, type, index) do
    {optional, required} = Enum.split_with(field.args, &InputValue.is_optional?/1)
    required = Enum.map(required, &arg(&1, index))
    optional = Enum.map(optional, &arg(&1, index))

    %Function{
      name: Naming.function(field.name),
      gql_name: field.name,
      doc: doc(field),
      deprecated: field.deprecation_reason && Naming.doc(field.deprecation_reason),
      self: self_var(type, required),
      required_args: required,
      optional_args: optional,
      return: return(field, type, index)
    }
  end

  # An argument may be named the same as the receiver; the receiver yields.
  defp self_var(type, required_args) do
    var = Naming.var(type.name)
    if Enum.any?(required_args, &(&1.name == var)), do: var <> "_", else: var
  end

  defp arg(input_value, index) do
    type = Type.normalize(input_value.type, expected(input_value, index))

    %Arg{
      name: Naming.var(input_value.name),
      gql_name: input_value.name,
      type: type,
      doc: doc(input_value),
      guard: guard(type, index)
    }
  end

  # Only the analyzer knows an enum's members, so it fills that guard in.
  defp guard(type, index) do
    case Type.guard(type) do
      :enum -> enum_guard(type, index)
      otherwise -> otherwise
    end
  end

  defp enum_guard({:enum, name}, index) do
    case get_in(index, [name, :enum_values]) do
      nil -> {:call, "is_atom"}
      [] -> {:call, "is_atom"}
      values -> {:in, Enum.map(values, &(":" <> &1))}
    end
  end

  # `@expectedType` says an `ID` argument really identifies some object. It never
  # applies to the argument literally named `id`, which is the id itself.
  defp expected(%InputValue{name: "id"}, _index), do: nil
  defp expected(%InputValue{directives: directives}, index), do: resolve(directives, index)

  defp resolve(directives, index) do
    case Directive.expected_type(directives) do
      nil -> nil
      name -> {get_in(index, [name, :kind]) || :interface, name}
    end
  end

  # The fallback above is `:interface` on purpose. A complete index makes it
  # unreachable, but the two ways of being wrong are not symmetric: guarding an
  # object with `is_struct/1` merely accepts more than it should, while matching
  # `%Dagger.Node{}` against an interface names a struct that does not exist.

  ## Return classification
  #
  # The one place a field's shape is decided. Both the `@spec` and the body are
  # rendered from the result, so they cannot disagree.

  defp return(field, type, index) do
    # An id-carrying field is classified on its own type, not on the type it
    # points at, so `@expectedType` is deliberately not passed to normalize/2.
    returned = Type.normalize(field.type)

    cond do
      Type.node?(Type.element(returned)) -> {:nodes, returned}
      Type.void?(returned) -> :void
      self_id?(field, type, index) -> {:node, type.name}
      Type.enum?(Type.element(returned)) -> {:list_of_enum, returned}
      Type.enum?(returned) -> {:enum, returned}
      Type.node?(returned) -> {:lazy, returned}
      true -> {:leaf, returned}
    end
  end

  # `sync` and friends: a scalar field whose `@expectedType` is the type it lives
  # on, i.e. an id that should be handed back as the object itself.
  defp self_id?(field, type, index) do
    case resolve(field.directives, index) do
      {_kind, name} -> field.name != "id" and name == type.name
      nil -> false
    end
  end

  ## Docs

  defp doc(%{description: description}) when description in [nil, ""], do: nil

  defp doc(%{description: description, directives: directives}) do
    Enum.reduce(directives, Naming.doc(description), &append_directive_doc/2)
  end

  defp doc(%{description: description}), do: Naming.doc(description)

  defp append_directive_doc(
         %Directive{name: "experimental", args: [%{name: "reason", value: reason}]},
         doc
       ) do
    doc <> "\n\n" <> admonition("Experimental", unquote_value(reason))
  end

  defp append_directive_doc(_directive, doc), do: doc

  defp admonition(title, text) do
    body = text |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))
    "> #### #{title} {: .warning}\n>\n" <> body
  end

  # Directive argument values arrive as GraphQL literals, quotes included.
  defp unquote_value(value), do: value |> String.trim_leading("\"") |> String.trim_trailing("\"")

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end

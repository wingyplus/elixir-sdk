defmodule Dagger.Codegen.IR do
  @moduledoc """
  What a generated module contains, decided once by the analyzer and printed by
  the renderer.

  The point of the split is that everything interesting — which arguments are
  required, how a value is encoded, what a function returns — is data here, so
  it can be asserted directly instead of only through the rendered string.
  """

  defmodule Arg do
    @moduledoc """
    A function argument, or an input object's field.

    `guard` is how a required argument is narrowed in the function head:

      * `{:call, fun}` — a plain guard, `is_binary(name)`
      * `{:is_struct, module}` — `is_struct(at, DateTime)`
      * `{:struct, module}` — matched in the head instead, `%Dagger.File{} = file`
      * `{:in, values}` — an enum, `kind in [:STRING_KIND, ...]`
      * `nil` — nothing useful can be checked

    Optional arguments carry `nil`: they arrive inside a keyword list, where
    there is no head to guard.
    """

    @type guard ::
            {:call, String.t()}
            | {:is_struct, String.t()}
            | {:struct, String.t()}
            | {:in, [String.t()]}
            | nil

    @type t :: %__MODULE__{
            name: String.t(),
            gql_name: String.t(),
            type: Dagger.Codegen.Type.t(),
            doc: String.t() | nil,
            guard: guard()
          }

    defstruct [:name, :gql_name, :type, :doc, :guard]
  end

  defmodule EnumValue do
    @moduledoc "One member of a GraphQL enum."

    @type t :: %__MODULE__{name: String.t(), value: String.t(), doc: String.t() | nil}

    defstruct [:name, :value, :doc]
  end

  defmodule Function do
    @moduledoc """
    A function on a generated object module.

    `return` is the single classification the renderer needs. It drives both the
    `@spec` and the function body, so the two cannot drift apart:

      * `{:lazy, type}` — an object or interface. No request is made; the
        function just extends the query and wraps it in a struct.
      * `{:leaf, type}` — a scalar, or a list of them. Executed as-is.
      * `:void` — executed for its effect, returns `:ok`.
      * `{:enum, type}` / `{:list_of_enum, type}` — executed, then mapped back
        from the wire string.
      * `{:nodes, type}` — a list of objects. Their ids are selected and each is
        rehydrated into a struct.
      * `{:node, module}` — a scalar field that is really an id for `module`
        (this is how `sync` returns the object it synced).
    """

    @type return ::
            {:lazy, Dagger.Codegen.Type.t()}
            | {:leaf, Dagger.Codegen.Type.t()}
            | :void
            | {:enum, Dagger.Codegen.Type.t()}
            | {:list_of_enum, Dagger.Codegen.Type.t()}
            | {:nodes, Dagger.Codegen.Type.t()}
            | {:node, String.t()}

    @type t :: %__MODULE__{
            name: String.t(),
            gql_name: String.t(),
            doc: String.t() | nil,
            deprecated: String.t() | nil,
            self: String.t(),
            required_args: [Arg.t()],
            optional_args: [Arg.t()],
            return: return()
          }

    defstruct [
      :name,
      :gql_name,
      :doc,
      :deprecated,
      :self,
      :return,
      required_args: [],
      optional_args: []
    ]
  end

  defmodule ModuleDef do
    @moduledoc """
    One generated Elixir module.

    Named `ModuleDef` rather than `Module` to stay clear of `Module`, and rather
    than `Mod` to stay clear of the SDK's own `Dagger.Mod`.
    """

    @type kind :: :object | :interface | :enum | :input | :scalar

    @type t :: %__MODULE__{
            module: String.t(),
            var: String.t(),
            gql_name: String.t(),
            kind: kind(),
            moduledoc: String.t(),
            derives: [String.t()],
            functions: [Function.t()],
            enum_values: [EnumValue.t()],
            fields: [Arg.t()]
          }

    defstruct [
      :module,
      :var,
      :gql_name,
      :kind,
      :moduledoc,
      derives: [],
      functions: [],
      enum_values: [],
      fields: []
    ]

    @doc "Whether the module gets the id-based protocol implementations."
    def node?(%__MODULE__{derives: derives}), do: "Dagger.ID" in derives
  end
end

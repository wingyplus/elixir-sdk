defmodule Dagger.Mod.Object do
  @moduledoc """
  Declare a module as an object type.

  ## Declare an object

  Add `use Dagger.Mod.Object` to the Elixir module that want to be a
  Dagger module and give a name through `:name` configuration:

      defmodule Potato do
        use Dagger.Mod.Object, name: "Potato"

        # ...
      end

  The module also support documentation by using Elixir standard documentation,
  `@moduledoc`.

  ## Declare a function

  The module provides a `defn`, a macro for declare a function.
  Let's declare a new function named `echo` that accepts a `name` as a string
  and return a container that echo a name in the module `Potato` from the previous
  section:

      defmodule Potato do
        use Dagger.Mod.Object, name: "Potato"

        defn echo(name: String.t()) :: Dagger.Container.t() do
          dag()
          |> Dagger.Client.container()
          |> Dagger.Container.from("alpine")
          |> Dagger.Container.with_exec(["echo", name])
        end
      end

  From the example above, the `defn` allows you to annotate a type to function
  arguments and return type by using Elixir Typespec. The type will convert to
  a Dagger type when registering a module.

  The supported types are:

  1. `integer()` for an integer type.
  2. `float()` for a float type.
  3. `boolean()` for a boolean type.
  4. `String.t()` or `binary()` for a string type.
  5. `list(type)` or `[type]` for a list type.
  6. `type | nil` for optional type.
  7. Any type that generated under `Dagger` namespace (`Dagger.Container.t()`,
     `Dagger.Directory.t()`, etc.).
  8. Any module that declares `use Dagger.Mod.Object` or `use Dagger.Mod.Enum`.

  The function also support documentation by using Elixir standard documentation,
  `@doc`.

  A function may take the object itself as its first argument by naming it
  `self`:

      defn with_name(self, name: String.t()) :: __MODULE__.t() do
        %__MODULE__{self | name: name}
      end

  ## Configure a function

  `defn` accepts an optional configuration after the return type. Use a bare
  atom for a single flag, or a list to combine several options:

      defn lint() :: Dagger.Void.t(), :check do
        # ...
      end

      defn build(source: Dagger.Directory.t()) :: Dagger.Container.t(),
             [:check, cache: {:ttl, "30s"}] do
        # ...
      end

  The supported options are:

  | Option | Value | Description |
  | ------ | ----- | ----------- |
  | `:check` | flag | Discover and run this function with `dagger check`. Takes no required arguments. |
  | `:generate` | flag | Register this function as a generator, run by `dagger generate` and, unless `--no-generate`, by `dagger check`. Returns `Dagger.Changeset.t()` and takes no required arguments. |
  | `cache:` | `:default` | Cache the result with the engine default policy. |
  | `cache:` | `:never` | Never cache the result. |
  | `cache:` | `:per_session` | Cache the result for the duration of a session. |
  | `cache:` | `{:ttl, duration}` | Cache the result for `duration`, e.g. `{:ttl, "30s"}`. |

  A cache `duration` is a duration string such as `"30s"`, `"10m"` or `"1h30m"`.
  The engine rejects a value outside 1 second to 7 days.

  See `defn/3` for the full grammar.

  ## Declare a constructor

  A function named `init` becomes the object constructor. It is called when the
  object is first created, and its return value becomes the object:

      defmodule Potato do
        use Dagger.Mod.Object, name: "Potato"

        object do
          field(:name, String.t())
        end

        defn init(name: {String.t(), default: "potato"}) :: __MODULE__.t() do
          %__MODULE__{name: name}
        end
      end

  `:check` and `:generate` cannot be used on `init`.

  ## Declare fields

  Use `object/1` and `field/3` to declare an object that carries state between
  function calls:

      object do
        field(:name, String.t())
        field(:size, integer() | nil)
      end

  A field typed as optional (`type | nil`) is not enforced when building the
  struct. `field/3` accepts `:doc` and `:deprecated`.

  ## Declare argument options

  An argument may carry options by wrapping its type in a tuple:

      defn entries(dir: {Dagger.Directory.t(), doc: "The directory.", default_path: "/"}) ::
             [String.t()] do
        # ...
      end

  The supported argument options are `:doc`, `:default`, `:default_path`,
  `:ignore` and `:deprecated`.

  ## Deprecation

  A module, function or argument can be marked as deprecated. Modules and
  functions use the standard Elixir annotations:

      @moduledoc deprecated: "Use `NewPotato` instead."

      @doc deprecated: "Use `echo2/1` instead."
      defn echo(name: String.t()) :: String.t() do
        # ...
      end

  An argument uses the `:deprecated` argument option.
  """

  @type function_name() :: atom()
  @type function_def() :: {function_name(), keyword()}

  alias Dagger.Mod.Object.Defn
  alias Dagger.Mod.Object.Meta
  alias Dagger.Mod.Object.Options

  @doc """
  Get module deprecation reason if deprecated from docs annotation metadata

  Return `{:deprecated, reason}` or `nil` if the module did not specify `@moduledoc deprecated: "reason"`
  """
  def get_module_deprecated(module) do
    with {_, metadatas, _} <- fetch_docs(module),
         %{deprecated: reason} <- metadatas do
      {:deprecated, reason}
    else
      _ -> nil
    end
  end

  @doc """
  Get function deprecation reason if deprecated from docs or attribute

  Return `{:deprecated, reason}` or `nil` if the function did not specify `@deprecated reason` attributes or `@doc deprecated: "reason" docstring`
  """
  def get_function_deprecated(module, func_name) do
    fun = fn
      {{:function, ^func_name, _}, _, _, _, _} -> true
      _ -> false
    end

    with {_, _, func_docs} <- fetch_docs(module),
         {{:function, ^func_name, _}, _, _, _, metadatas} <- Enum.find(func_docs, fun),
         %{deprecated: reason} <- metadatas do
      {:deprecated, reason}
    else
      _ ->
        nil
    end
  end

  @doc """
  Get module documentation.

  Returns module doc string or `nil` if the given module didn't have a documentation.
  """
  @spec get_module_doc(module()) :: String.t() | nil
  def get_module_doc(module) do
    with {module_doc, _, _} <- fetch_docs(module),
         %{"en" => doc} <- module_doc do
      String.trim(doc)
    else
      :none -> nil
      :hidden -> nil
      {:error, :module_not_found} -> nil
    end
  end

  @doc """
  Get function documentation.

  Return doc string or `nil` if that function didn't have a documentation.
  """
  @spec get_function_doc(module(), function_name()) :: String.t() | nil
  def get_function_doc(module, name) do
    fun = fn
      {{:function, ^name, _}, _, _, _, _} -> true
      _ -> false
    end

    with {_, _, function_docs} <- fetch_docs(module),
         {{:function, ^name, _}, _, _, doc_content, _} <- Enum.find(function_docs, fun),
         %{"en" => doc} <- doc_content do
      String.trim(doc)
    else
      nil -> nil
      :none -> nil
      :hidden -> nil
    end
  end

  defp fetch_docs(module) do
    {:docs_v1, _, :elixir, _, module_doc, metadatas, function_docs} = Code.fetch_docs(module)
    {module_doc, metadatas, function_docs}
  end

  defmacro __before_compile__(env) do
    if Module.get_attribute(env.module, :struct_declared) do
      required_fields = Module.get_attribute(env.module, :required_fields) || []
      optional_fields = Module.get_attribute(env.module, :optional_fields) || []
      fields = required_fields ++ optional_fields
      fields = Macro.escape(fields)

      quote do
        defimpl Nestru.Decoder do
          def decode_fields_hint(_empty_struct, _context, _value) do
            {:ok, Dagger.Mod.Object.decoder_hint(unquote(fields))}
          end
        end
      end
    else
      quote do
      end
    end
  end

  defmacro __using__(opts) do
    name = opts[:name]

    quote do
      use Dagger.Core.Base, kind: :object, name: unquote(name)

      import Dagger.Mod.Object, only: [defn: 2, defn: 3, field: 2, field: 3, object: 1]
      import Dagger.Global, only: [dag: 0]

      Module.register_attribute(__MODULE__, :function, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :field, accumulate: true, persist: true)

      @before_compile Dagger.Mod.Object

      # Get an object name
      def __object__(:name), do: unquote(name)

      # List available function definitions.
      def __object__(:functions) do
        __MODULE__.__info__(:attributes)
        |> Keyword.get_values(:function)
        |> Enum.flat_map(& &1)
      end

      # Get a function definition.
      def __object__(:function, name) do
        __object__(:functions)
        |> Keyword.fetch!(name)
      end

      # List available field definitions.
      def __object__(:fields) do
        __MODULE__.__info__(:attributes)
        |> Keyword.get_values(:field)
        |> Enum.flat_map(& &1)
      end
    end
  end

  @doc """
  Declare a function.

  See `defn/3` to configure the declared function.
  """
  defmacro defn(call, do: block) do
    build(call, [], block)
  end

  @doc """
  Declare a function with configuration.

  The configuration is either a single flag, written as a bare atom, or a list
  combining flags and keyword pairs:

      defn lint() :: Dagger.Void.t(), :check do
        # ...
      end

      defn build(source: Dagger.Directory.t()) :: Dagger.Container.t(),
             [:check, cache: {:ttl, "30s"}] do
        # ...
      end

  ## Flags

    * `:check` - discover and run this function with `dagger check`. The
      function fails the check when it raises, or when it returns a container
      whose last command exits non-zero.

      A check must be callable with no arguments, because `dagger check` runs
      it on its own.

    * `:generate` - register this function as a generator, run by
      `dagger generate`. Generators also run as part of `dagger check` unless
      it is given `--no-generate`. A function declared with both `:check` and
      `:generate` runs once, as a check.

      A generator must return `Dagger.Changeset.t()` and, like a check, be
      callable with no arguments.

  An argument does not count against "no arguments" when the engine can supply
  it: one carrying a `:default` or a `:default_path`, or typed as optional
  (`type | nil`). The object itself, taken as `self`, never counts.

  ## Options

    * `:cache` - the caching behaviour of the function result. One of:

        * `:default` - the engine default policy.
        * `:never` - never cache the result.
        * `:per_session` - cache the result for the duration of a session.
        * `{:ttl, duration}` - cache the result for `duration`.

      A `duration` is a duration string such as `"30s"`, `"10m"` or `"1h30m"`.
      The shape is checked when the module compiles; the engine rejects a
      value outside 1 second to 7 days when the module is served.

  Both flags and options are validated when the module is compiled, so an
  unknown option, a bad cache policy, a malformed duration or a flag whose
  contract the signature breaks raises an `ArgumentError` pointing at the
  `defn` that declared it.

  Neither `:check` nor `:generate` can be used on `init`, which declares the
  object constructor rather than a callable function.
  """
  defmacro defn(call, opts, do: block) do
    build(call, opts, block)
  end

  # Builds the AST for both `defn/2` and `defn/3`. This runs at expansion time,
  # so any option error is raised against the `defn` call site.
  defp build(call, opts, block) do
    {name, args, return} = extract_call(call)
    has_self? = is_tuple(args)
    arg_defs = compile_args(args)
    return_def = compile_typespec!(return)
    fun_opts = Options.normalize!(opts, name)
    :ok = Options.validate_signature!(fun_opts, name, arg_defs, return_def)

    quote do
      @function {unquote(name),
                 %Dagger.Mod.Object.FunctionDef{
                   self: unquote(has_self?),
                   cache_policy: unquote(fun_opts[:cache]),
                   check: unquote(fun_opts[:check]),
                   generate: unquote(fun_opts[:generate]),
                   args: unquote(arg_defs),
                   return: unquote(return_def)
                 }}
      unquote(Defn.define(name, args, return, block))
    end
  end

  @doc """
  Declare an object struct.
  """
  defmacro object(do: block) do
    quote do
      Module.register_attribute(__MODULE__, :required_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :optional_fields, accumulate: true)

      unquote(block)

      required_fields = @required_fields || []
      optional_fields = @optional_fields || []
      fields = @required_fields ++ @optional_fields

      # TODO: convert fields into typespec.
      @type t() :: %__MODULE__{}

      @derive Jason.Encoder
      @enforce_keys Keyword.keys(required_fields)
      defstruct fields |> Keyword.keys() |> Enum.sort()

      @struct_declared true
    end
  end

  def decoder_hint(fields) do
    fields
    |> Enum.filter(&only_module/1)
    |> Enum.into(%{}, fn {name, field_def} ->
      type =
        case field_def.type do
          {:list, type} -> type
          {:optional, type} -> type
          type -> type
        end

      {name, type}
    end)
  end

  defp only_module({_, field_def}) do
    case field_def.type do
      {:list, type} -> module?(type)
      {:optional, type} -> module?(type)
      type -> module?(type)
    end
  end

  defp module?(type) do
    {:module, ^type} = Code.ensure_loaded(type)
    function_exported?(type, :__struct__, 0)
  end

  @doc """
  Declare a field.
  """
  defmacro field(name, type, opts \\ []) do
    type = compile_typespec!(type)
    optional? = match?({:optional, _}, type)
    doc = opts[:doc]
    deprecated = opts[:deprecated]

    field =
      Macro.escape(
        {name, %Dagger.Mod.Object.FieldDef{type: type, doc: doc, deprecated: deprecated}}
      )

    quote do
      @field unquote(field)
      if unquote(optional?) do
        Module.put_attribute(__MODULE__, :optional_fields, unquote(field))
      else
        Module.put_attribute(__MODULE__, :required_fields, unquote(field))
      end
    end
  end

  defguardp is_self(self) when is_atom(elem(self, 0)) and is_nil(elem(self, 2))
  defguardp is_args(args) when is_list(args)

  defp extract_call({:"::", _, [call_def, return]}) do
    {name, args} = extract_call_def(call_def)
    {name, args, return}
  end

  defp extract_call_def({name, _, []}) do
    {name, []}
  end

  defp extract_call_def({name, _, [self]}) when is_self(self) do
    {name, {self, []}}
  end

  defp extract_call_def({name, _, [args]}) when is_args(args) do
    {name, args}
  end

  defp extract_call_def({name, _, [self, args]}) when is_self(self) and is_args(args) do
    {name, {self, args}}
  end

  defp compile_args({_, args}) do
    compile_args(args)
  end

  defp compile_args(args) do
    for {name, spec} <- args do
      type = compile_typespec!(spec)
      meta = spec |> extract_options() |> Keyword.put(:type, type)
      {name, Meta.validate!(meta)}
    end
  end

  defp compile_typespec!({:integer, _, []}), do: :integer
  defp compile_typespec!({:float, _, []}), do: :float
  defp compile_typespec!({:boolean, _, []}), do: :boolean

  ## List

  defp compile_typespec!({:list, _, [type]}) do
    {:list, compile_typespec!(type)}
  end

  defp compile_typespec!([type]) do
    {:list, compile_typespec!(type)}
  end

  ## Optional

  defp compile_typespec!(
         {{{:., _,
            [
              {:__aliases__, _, [_type]},
              :t
            ]}, _, []} = type, [default: _default_value]}
       ) do
    {:optional, compile_typespec!(type)}
  end

  defp compile_typespec!({:|, _, [type, nil]}) do
    {:optional, compile_typespec!(type)}
  end

  ## Type with options

  defp compile_typespec!({type, _}) do
    compile_typespec!(type)
  end

  ## String

  defp compile_typespec!({:binary, _, []}), do: :string

  defp compile_typespec!(
         {{:., _,
           [
             {:__aliases__, _, [:String]},
             :t
           ]}, _, []}
       ) do
    :string
  end

  defp compile_typespec!({{:., _, [{:__aliases__, _, module}, :t]}, _, []}) do
    Module.concat(module)
  end

  defp compile_typespec!(unsupported_type) do
    raise ArgumentError, "type `#{Macro.to_string(unsupported_type)}` is not supported"
  end

  defp extract_options({_, options}), do: options
  defp extract_options(_), do: []
end

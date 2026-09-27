defmodule Dagger.Mod.Object do
  @moduledoc """
  Write a Dagger module object in Elixir.

  An object groups functions that can be called with `dagger call`. Each
  Dagger module has at least one object, named after the module.

  ## Declare an object

  Add `use Dagger.Mod.Object` to a module and give the object a name:

      defmodule Potato do
        @moduledoc \"""
        A potato module.
        \"""

        use Dagger.Mod.Object, name: "Potato"
      end

  The `@moduledoc` becomes the object description shown to users.

  ## Declare a function

  Use `defn` to declare a function. Arguments are written as a keyword list of
  names and types, followed by the return type:

      defmodule Potato do
        use Dagger.Mod.Object, name: "Potato"

        @doc \"""
        Print a name.
        \"""
        defn echo(name: String.t()) :: Dagger.Container.t() do
          dag()
          |> Dagger.Client.container()
          |> Dagger.Container.from("alpine")
          |> Dagger.Container.with_exec(["echo", name])
        end
      end

  The `@doc` becomes the function description, and `dag/0` gives you the
  Dagger client to call the Dagger API with.

  The function is then available from the command line:

      dagger call echo --name=potato

  ## Supported types

  * `integer()` - an integer.
  * `float()` - a float.
  * `boolean()` - a boolean.
  * `String.t()` or `binary()` - a string.
  * `list(type)` or `[type]` - a list of `type`.
  * `type | nil` - an optional `type`.
  * Any type from the Dagger API, such as `Dagger.Container.t()` or
    `Dagger.Directory.t()`.
  * Any module that uses `Dagger.Mod.Object` or `Dagger.Mod.Enum`, such as
    `Potato.t()`.

  ## Argument options

  An argument can carry options by wrapping its type in a tuple:

      defn entries(dir: {Dagger.Directory.t(), doc: "The directory.", default_path: "/"}) ::
             [String.t()] do
        # ...
      end

  | Option          | Description                                                            |
  | --------------- | ---------------------------------------------------------------------- |
  | `:doc`          | The argument description.                                              |
  | `:default`      | The value used when the argument is not given.                         |
  | `:default_path` | The path to load a `Dagger.Directory` or `Dagger.File` from by default. |
  | `:ignore`       | Patterns to exclude from a `Dagger.Directory` argument.                |
  | `:deprecated`   | Mark the argument as deprecated, with a reason.                        |

  ## Optional arguments

  An argument with a `:default`, or typed as optional (`type | nil`), can be
  left out, both from the command line and when calling the function from
  Elixir:

      defn greet(name: String.t() | nil, greeting: {String.t(), default: "Hello"}) ::
             String.t() do
        "\#{greeting}, \#{name}"
      end

      greet()
      #=> "Hello, "

  Declare required arguments before optional ones. Like any Elixir default
  argument, an optional argument placed before a required one changes which
  argument the shorter call fills in.

  ## Keep state in an object

  Use `object/1` and `field/3` to declare fields that are kept between
  function calls:

      defmodule Potato do
        use Dagger.Mod.Object, name: "Potato"

        object do
          field(:name, String.t(), doc: "The potato name.")
          field(:size, integer() | nil)
        end
      end

  A field typed as optional (`type | nil`) does not have to be set.

  A function can read and update the object by taking `self` as its first
  argument:

      defn with_name(self, name: String.t()) :: __MODULE__.t() do
        %__MODULE__{self | name: name}
      end

  ## Declare a constructor

  A function named `init` is the constructor. Its arguments become the
  arguments of the module, and it returns the object:

      defn init(name: {String.t(), default: "potato"}) :: __MODULE__.t() do
        %__MODULE__{name: name}
      end

  ## Function flags

  A function can have one flag, written after the return type, to be run by a
  specific `dagger` command:

      defn lint() :: Dagger.Void.t(), :check do
        # ...
      end

  | Flag        | Description                                                                                                                                                |
  | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | `:check`    | Run the function with `dagger check`. It must not have required arguments.                                                                                 |
  | `:generate` | Run the function with `dagger generate` and `dagger check`. It must return `Dagger.Changeset.t()` and not have required arguments.                         |
  | `:up`       | Start the returned service with `dagger up`. It must return `Dagger.Service.t()` and not have required arguments.                                          |
  | `:agent`    | Use the function as agent middleware with `dagger agent`. It must return `Dagger.LLM.t()` and take a single required `Dagger.LLM.t()` argument.            |

  The constructor `init` cannot have a flag.

  ## Function caching

  Use the `:cache` option to control how long a function result is cached:

      defn version() :: String.t(), cache: :never do
        # ...
      end

      defn build(source: Dagger.Directory.t()) :: Dagger.Container.t(), :check, cache: {:ttl, "30s"} do
        # ...
      end

  | Value              | Description                                           |
  | ------------------ | ----------------------------------------------------- |
  | `:default`         | Use the engine default.                               |
  | `:never`           | Never cache the result.                               |
  | `:per_session`     | Cache the result for the duration of a session.       |
  | `{:ttl, duration}` | Cache the result for `duration`, such as `"30s"`, `"10m"` or `"1h30m"`, between 1 second and 7 days. |

  See `defn/4` for more details on flags and options.

  ## Deprecation

  Mark a module or a function as deprecated with the standard Elixir
  annotations:

      @moduledoc deprecated: "Use `NewPotato` instead."

      @doc deprecated: "Use `echo2/1` instead."
      defn echo(name: String.t()) :: String.t() do
        # ...
      end

  Mark a field or an argument as deprecated with the `:deprecated` option:

      field(:name, String.t(), deprecated: "Use `:title` instead.")

      defn echo(name: {String.t(), deprecated: "Use `title` instead."}) :: String.t() do
        # ...
      end

  To deprecate an enum member, see `Dagger.Mod.Enum`.
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
  def get_module_deprecated(module), do: docs(module).deprecated

  @doc """
  Get function deprecation reason if deprecated from docs or attribute

  Return `{:deprecated, reason}` or `nil` if the function did not specify `@deprecated reason` attributes or `@doc deprecated: "reason" docstring`
  """
  def get_function_deprecated(module, func_name) do
    module |> docs() |> function_docs(func_name) |> elem(1)
  end

  @doc """
  Get module documentation.

  Returns module doc string or `nil` if the given module didn't have a documentation.
  """
  @spec get_module_doc(module()) :: String.t() | nil
  def get_module_doc(module), do: docs(module).doc

  @doc """
  Get function documentation.

  Return doc string or `nil` if that function didn't have a documentation.
  """
  @spec get_function_doc(module(), function_name()) :: String.t() | nil
  def get_function_doc(module, name) do
    module |> docs() |> function_docs(name) |> elem(0)
  end

  defp function_docs(docs, name), do: Map.get(docs.functions, name, {nil, nil})

  @doc false
  # Everything registration reads from the documentation of `module`, which
  # `Code.fetch_docs/1` reads from the module's .beam file each time it is
  # called: the module's doc and deprecation, and each function's, by name.
  def docs(module) do
    {:docs_v1, _, :elixir, _, module_doc, metadata, function_docs} = Code.fetch_docs(module)

    functions =
      for {{:function, name, _}, _, _, doc, metadata} <- Enum.reverse(function_docs),
          into: %{},
          # Reversed, so that the first entry of a name is the one kept.
          do: {name, {doc_text(doc), deprecated(metadata)}}

    %{doc: doc_text(module_doc), deprecated: deprecated(metadata), functions: functions}
  end

  defp doc_text(%{"en" => doc}), do: String.trim(doc)
  defp doc_text(_none_or_hidden), do: nil

  defp deprecated(%{deprecated: reason}), do: {:deprecated, reason}
  defp deprecated(_metadata), do: nil

  defmacro __before_compile__(env) do
    quote do
      unquote(object_table(env))
    end
  end

  # The declarations, read from the attributes they accumulate in while the
  # module compiles and written into the module as constants. Read back through
  # `__info__(:attributes)` instead, every lookup decoded all of them again, so
  # finding one function cost as much as the whole module has.
  defp object_table(env) do
    functions = declared(env.module, :function)
    fields = declared(env.module, :field)

    quote do
      def __object__(:functions), do: unquote(Macro.escape(functions))

      def __object__(:fields), do: unquote(Macro.escape(fields))

      def __object__(:name), do: unquote(Module.get_attribute(env.module, :dagger_object_name))

      # Get a function definition.
      def __object__(:function, name) do
        Keyword.fetch!(__object__(:functions), name)
      end
    end
  end

  defp declared(module, attribute) do
    module |> Module.get_attribute(attribute) |> Enum.reverse()
  end

  defmacro __using__(opts) do
    name = opts[:name]

    quote do
      use Dagger.Core.Base, kind: :object, name: unquote(name)

      import Dagger.Mod.Object, only: [defn: 2, defn: 3, defn: 4, field: 2, field: 3, object: 1]
      import Dagger.Global, only: [dag: 0]

      Module.register_attribute(__MODULE__, :function, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :field, accumulate: true, persist: true)

      @dagger_object_name unquote(name)
      @before_compile Dagger.Mod.Object
    end
  end

  @doc """
  Declare a function.

  See `defn/4` to configure the declared function.
  """
  defmacro defn(call, do: block) do
    build(call, nil, [], block)
  end

  @doc """
  Declare a function with a flag or with options.

  The second argument is either a flag, written as a bare atom, or a keyword
  list of options:

      defn lint() :: Dagger.Void.t(), :check do
        # ...
      end

      defn build(source: Dagger.Directory.t()) :: Dagger.Container.t(),
             cache: {:ttl, "30s"} do
        # ...
      end

  See `defn/4` for both at once, and for what each flag and option means.
  """
  defmacro defn(call, flag, do: block) when is_atom(flag) do
    build(call, flag, [], block)
  end

  defmacro defn(call, opts, do: block) do
    build(call, nil, opts, block)
  end

  @doc """
  Declare a function with a flag and options.

  The flag comes right after the return type, and the options after it:

      defn hello() :: Dagger.Container.t(), :check, cache: {:ttl, "30s"} do
        # ...
      end

  A function declares at most one flag, so the flag is a bare atom rather than
  a list: `:check`, `:generate`, `:up` and `:agent` each run the function a
  different way, and a function is one of them, never several at once.

  ## Flags

    * `:check` - discover and run this function with `dagger check`. The
      function fails the check when it raises, or when it returns a container
      whose last command exits non-zero.

      A check must be callable with no arguments, because `dagger check` runs
      it on its own.

    * `:generate` - register this function as a generator, run by
      `dagger generate`. Generators also run as part of `dagger check` unless
      it is given `--no-generate`.

      A generator must return `Dagger.Changeset.t()` and, like a check, be
      callable with no arguments.

    * `:up` - start the service this function returns with `dagger up`.

      An up function must return `Dagger.Service.t()` and be callable with no
      arguments.

    * `:agent` - register this function as agent middleware, discovered and
      composed by `dagger agent`.

      An agent must return `Dagger.LLM.t()` and require exactly one argument,
      the base `Dagger.LLM.t()` the compose fold supplies. Any other argument
      it declares has to be one the caller can leave out.

  An argument does not count against "no arguments" when the engine can supply
  it: one carrying a `:default` or a `:default_path`, or typed as optional
  (`type | nil`). The object itself, taken as `self`, never counts. The base an
  `:agent` requires is the one exception: it is a required argument, and the
  only one an agent may declare.

  ## Options

    * `:cache` - the caching behaviour of the function result. One of:

        * `:default` - the engine default policy.
        * `:never` - never cache the result.
        * `:per_session` - cache the result for the duration of a session.
        * `{:ttl, duration}` - cache the result for `duration`.

      A `duration` is a duration string such as `"30s"`, `"10m"` or `"1h30m"`.
      The shape is checked when the module compiles; the engine rejects a
      value outside 1 second to 7 days when the module is served.

  The flag and the options are validated when the module is compiled, so an
  unknown flag, an unknown option, a bad cache policy, a malformed duration, or
  a flag whose contract the signature breaks raises an `ArgumentError` pointing
  at the `defn` that declared it.

  No flag can be used on `init`, which declares the object constructor rather
  than a callable function.
  """
  defmacro defn(call, flag, opts, do: block) do
    build(call, flag, opts, block)
  end

  # Builds the AST for every `defn` arity. This runs at expansion time, so any
  # flag or option error is raised against the `defn` call site.
  defp build(call, flag, opts, block) do
    {name, args, return} = extract_call(call)
    has_self? = is_tuple(args)
    arg_defs = compile_args(args)
    return_def = compile_typespec!(return)
    fun_opts = Options.normalize!(flag, opts, name)
    :ok = Options.validate_signature!(fun_opts, name, arg_defs, return_def)

    quote do
      @function {unquote(name),
                 %Dagger.Mod.Object.FunctionDef{
                   self: unquote(has_self?),
                   cache_policy: unquote(fun_opts[:cache]),
                   check: unquote(fun_opts[:check]),
                   generate: unquote(fun_opts[:generate]),
                   up: unquote(fun_opts[:up]),
                   agent: unquote(fun_opts[:agent]),
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

      @derive JSON.Encoder
      @enforce_keys Keyword.keys(required_fields)
      defstruct fields |> Keyword.keys() |> Enum.sort()
    end
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

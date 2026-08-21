defmodule Dagger.Mod.ObjectTest do
  use ExUnit.Case, async: true

  alias Dagger.Mod.Object.FunctionDef

  defp defn_options(fun_name, opts), do: Dagger.Mod.Object.Options.normalize!(opts, fun_name)
  alias Dagger.Mod.Object.FieldDef

  describe "defn/2" do
    test "primitive type arguments" do
      assert PrimitiveTypeArgs.__object__(:functions) == [
               accept_string: %FunctionDef{
                 self: false,
                 args: [
                   name: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, :string}
                   ]
                 ],
                 return: :string
               },
               accept_string2: %FunctionDef{
                 self: false,
                 args: [
                   name: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, :string}
                   ]
                 ],
                 return: :string
               },
               accept_integer: %FunctionDef{
                 self: false,
                 args: [
                   value: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, :integer}
                   ]
                 ],
                 return: :integer
               },
               accept_float: %FunctionDef{
                 self: false,
                 args: [
                   value: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, :float}
                   ]
                 ],
                 return: :float
               },
               accept_boolean: %FunctionDef{
                 self: false,
                 args: [
                   name: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, :boolean}
                   ]
                 ],
                 return: :string
               }
             ]
    end

    test "primitive type default arguments" do
      assert PrimitiveTypeDefaultArgs.__object__(:functions) == [
               accept_default_string: %FunctionDef{
                 self: false,
                 args: [
                   name: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:doc, nil},
                     {:type, {:optional, :string}},
                     {:default, "Foo"}
                   ]
                 ],
                 return: :string
               },
               accept_default_integer: %FunctionDef{
                 self: false,
                 args: [
                   value: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:doc, nil},
                     {:type, :integer},
                     {:default, 42}
                   ]
                 ],
                 return: :integer
               },
               accept_default_float: %FunctionDef{
                 self: false,
                 args: [
                   value: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:doc, nil},
                     {:type, :float},
                     {:default, 1.6180342}
                   ]
                 ],
                 return: :float
               },
               accept_default_boolean: %FunctionDef{
                 self: false,
                 args: [
                   value: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:doc, nil},
                     {:type, :boolean},
                     {:default, false}
                   ]
                 ],
                 return: :boolean
               }
             ]
    end

    test "empty arguments" do
      assert EmptyArgs.__object__(:functions) == [
               empty_args: %FunctionDef{self: false, args: [], return: :string}
             ]
    end

    test "accept and return object" do
      assert ObjectArgAndReturn.__object__(:functions) == [
               accept_and_return_module: %FunctionDef{
                 self: false,
                 args: [
                   container: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, Dagger.Container}
                   ]
                 ],
                 return: Dagger.Container
               }
             ]
    end

    test "list arguments" do
      assert ListArgs.__object__(:functions) == [
               accept_list: %FunctionDef{
                 self: false,
                 args: [
                   alist: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, {:list, :string}}
                   ]
                 ],
                 return: :string
               },
               accept_list2: %FunctionDef{
                 self: false,
                 args: [
                   alist: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, {:list, :string}}
                   ]
                 ],
                 return: :string
               }
             ]
    end

    test "optional arguments" do
      assert OptionalArgs.__object__(:functions) == [
               optional_arg: %FunctionDef{
                 self: false,
                 args: [
                   s: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, {:optional, :string}}
                   ]
                 ],
                 return: :string
               }
             ]
    end

    test "argument options" do
      assert ArgOptions.__object__(:functions) == [
               type_option: %FunctionDef{
                 self: false,
                 args: [
                   dir: [
                     {:default, nil},
                     {:deprecated, nil},
                     {:type, {:optional, Dagger.Directory}},
                     {:doc, "The directory to run on."},
                     {:default_path, "/sdk/elixir"},
                     {:ignore, ["deps", "_build"]}
                   ]
                 ],
                 return: :string
               }
             ]
    end

    test "return void" do
      assert ReturnVoid.__object__(:functions) == [
               return_void: %FunctionDef{self: false, args: [], return: Dagger.Void}
             ]
    end

    test "self object" do
      assert SelfObject.__object__(:functions) == [
               only_self_arg: %FunctionDef{self: true, args: [], return: Dagger.Void},
               mix_self_and_args: %FunctionDef{
                 self: true,
                 args: [
                   name: [
                     {:ignore, nil},
                     {:deprecated, nil},
                     {:default_path, nil},
                     {:default, nil},
                     {:doc, nil},
                     {:type, :string}
                   ]
                 ],
                 return: Dagger.Void
               }
             ]
    end

    test "throw unsupported type" do
      assert_raise ArgumentError, "type `non_neg_integer()` is not supported", fn ->
        defmodule ShouldThrowError do
          use Dagger.Mod.Object, name: "ShouldThrowError"

          defn accept_string(name: non_neg_integer()) :: String.t() do
            "Hello, #{name}"
          end
        end
      end
    end

    test "store the module name" do
      defmodule C do
        use Dagger.Mod.Object, name: "C"

        defn hello(name: String.t()) :: String.t() do
          "Hello, #{name}"
        end
      end

      assert C.__object__(:name) == "C"
    end

    test "typespec" do
      {:ok, specs} = Code.Typespec.fetch_specs(DocModule)

      fun_specs =
        Enum.flat_map(specs, fn {{name, _}, specs} ->
          specs
          |> Enum.map(fn spec -> Code.Typespec.spec_to_quoted(name, spec) end)
          |> Enum.map(fn spec -> quote(do: @spec(unquote(spec))) end)
          |> Enum.map(&Macro.to_string/1)
          |> Enum.sort()
        end)

      assert fun_specs == [
               "@spec no_fun_doc() :: String.t()",
               "@spec hidden_fun_doc() :: String.t()",
               "@spec echo(name :: String.t()) :: String.t()"
             ]
    end

    test "check option" do
      assert CheckOption.__object__(:functions) == [
               checked_function: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Void,
                 check: true,
                 generate: false
               },
               unchecked_function: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Void,
                 check: false,
                 generate: false
               }
             ]
    end

    test "generate option" do
      assert [
               generator_function: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Changeset,
                 check: false,
                 generate: true
               },
               generator_with_optional_arg: %FunctionDef{
                 self: false,
                 return: Dagger.Changeset,
                 check: false,
                 generate: true
               }
             ] = GenerateOption.__object__(:functions)
    end

    test "cache option" do
      assert CacheOption.__object__(:functions) == [
               default_cached: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Void,
                 check: false,
                 generate: false,
                 cache_policy: :default
               },
               never_cached: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Void,
                 check: false,
                 generate: false,
                 cache_policy: :never
               },
               per_session_cached: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Void,
                 check: false,
                 generate: false,
                 cache_policy: :per_session
               },
               ttl_cached: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Void,
                 check: false,
                 generate: false,
                 cache_policy: {:ttl, "42s"}
               },
               uncached: %FunctionDef{
                 self: false,
                 args: [],
                 return: Dagger.Void,
                 check: false,
                 generate: false,
                 cache_policy: nil
               }
             ]
    end

    test "combining flags and options" do
      assert [
               everything: %FunctionDef{
                 check: true,
                 generate: true,
                 cache_policy: {:ttl, "1h30m"}
               }
             ] = CombinedOptions.__object__(:functions)
    end

    test "option validation" do
      assert_raise ArgumentError, ~r/unknown option :ttl for `defn f`/, fn ->
        defn_options(:f, ttl: "30s")
      end

      assert_raise ArgumentError, ~r/unknown option :up for `defn f`/, fn ->
        defn_options(:f, :up)
      end

      assert_raise ArgumentError, ~r/expected :check to be a boolean/, fn ->
        defn_options(:f, check: "yes")
      end

      assert_raise ArgumentError, ~r/invalid cache ttl "1 hour"/, fn ->
        defn_options(:f, cache: {:ttl, "1 hour"})
      end

      assert_raise ArgumentError, ~r/invalid `cache` option :bogus/, fn ->
        defn_options(:f, cache: :bogus)
      end

      assert_raise ArgumentError, ~r/option :check was given more than once/, fn ->
        defn_options(:f, [:check, check: true])
      end

      assert_raise ArgumentError, ~r/:check cannot be used on `defn init`/, fn ->
        defn_options(:init, :check)
      end

      assert_raise ArgumentError, ~r/:generate cannot be used on `defn init`/, fn ->
        defn_options(:init, :generate)
      end
    end

    test "a generator must return a changeset" do
      assert_raise ArgumentError,
                   ~r/`defn gen` is declared :generate, so it must return `Dagger\.Changeset\.t\(\)`, got: `Dagger\.Void\.t\(\)`/,
                   fn ->
                     defmodule GenerateReturnsVoid do
                       use Dagger.Mod.Object, name: "GenerateReturnsVoid"

                       defn gen() :: Dagger.Void.t(), :generate do
                         :ok
                       end
                     end
                   end

      assert_raise ArgumentError,
                   ~r/`defn gen` is declared :generate, so it must return `Dagger\.Changeset\.t\(\)`, got: `String\.t\(\)`/,
                   fn ->
                     defmodule GenerateReturnsString do
                       use Dagger.Mod.Object, name: "GenerateReturnsString"

                       defn gen() :: String.t(), :generate do
                         "nope"
                       end
                     end
                   end

      assert_raise ArgumentError,
                   ~r/`defn gen` is declared :generate, so it must return `Dagger\.Changeset\.t\(\)`, got: `\[Dagger\.Changeset\.t\(\)\]`/,
                   fn ->
                     defmodule GenerateReturnsList do
                       use Dagger.Mod.Object, name: "GenerateReturnsList"

                       defn gen() :: [Dagger.Changeset.t()], :generate do
                         []
                       end
                     end
                   end
    end

    test "a generator return type must not be optional" do
      assert_raise ArgumentError,
                   ~r/the return type of `defn gen` must not be optional because it is declared :generate/,
                   fn ->
                     defmodule GenerateReturnsOptional do
                       use Dagger.Mod.Object, name: "GenerateReturnsOptional"

                       defn gen() :: Dagger.Changeset.t() | nil, :generate do
                         nil
                       end
                     end
                   end
    end

    test "a check or a generator cannot take a required argument" do
      assert_raise ArgumentError,
                   ~r/`defn lint` is declared :check, so it must be callable with no arguments, but `name` is required/,
                   fn ->
                     defmodule CheckWithRequiredArg do
                       use Dagger.Mod.Object, name: "CheckWithRequiredArg"

                       defn lint(name: String.t()) :: Dagger.Void.t(), :check do
                         _ = name
                         :ok
                       end
                     end
                   end

      assert_raise ArgumentError,
                   ~r/`defn gen` is declared :generate, so it must be callable with no arguments, but `name` is required/,
                   fn ->
                     defmodule GenerateWithRequiredArg do
                       use Dagger.Mod.Object, name: "GenerateWithRequiredArg"

                       defn gen(name: String.t()) :: Dagger.Changeset.t(), :generate do
                         _ = name
                         dag() |> Dagger.Client.changeset()
                       end
                     end
                   end

      # A `Dagger.Directory.t()` without a `:default_path` is still required.
      assert_raise ArgumentError,
                   ~r/`defn gen` is declared :generate, so it must be callable with no arguments, but `dir` is required/,
                   fn ->
                     defmodule GenerateWithRequiredDirArg do
                       use Dagger.Mod.Object, name: "GenerateWithRequiredDirArg"

                       defn gen(dir: Dagger.Directory.t()) :: Dagger.Changeset.t(), :generate do
                         _ = dir
                         dag() |> Dagger.Client.changeset()
                       end
                     end
                   end

      assert_raise ArgumentError,
                   ~r/but `name`, `dir` are required/,
                   fn ->
                     defmodule CheckWithTwoRequiredArgs do
                       use Dagger.Mod.Object, name: "CheckWithTwoRequiredArgs"

                       defn lint(name: String.t(), dir: Dagger.Directory.t()) ::
                              Dagger.Void.t(),
                            :check do
                         _ = {name, dir}
                         :ok
                       end
                     end
                   end
    end

    test "signatures a check or a generator accepts" do
      assert [
               check_with_self: %FunctionDef{self: true, args: [], check: true},
               generate_with_self: %FunctionDef{
                 self: true,
                 args: [],
                 return: Dagger.Changeset,
                 generate: true
               },
               check_with_default: %FunctionDef{check: true},
               check_with_default_path: %FunctionDef{check: true},
               check_with_optional: %FunctionDef{check: true},
               generate_with_default_path: %FunctionDef{
                 return: Dagger.Changeset,
                 generate: true
               }
             ] = FlagSignatures.__object__(:functions)
    end

    test "options are optional and default to off" do
      assert Dagger.Mod.Object.Options.normalize!([], :f) ==
               [check: false, generate: false, cache: nil]

      assert Dagger.Mod.Object.Options.normalize!(:check, :f)[:check]
      assert Dagger.Mod.Object.Options.normalize!([cache: :never], :init)[:cache] == :never
    end

    test "type option validation" do
      assert_raise FunctionClauseError, fn ->
        defmodule TypeOptDoc do
          use Dagger.Mod.Object, name: "TypeOptDoc"

          defn should_fail(v: {Dagger.String.t(), doc: 1}) :: String.t() do
            v
          end
        end
      end

      assert_raise FunctionClauseError, fn ->
        defmodule TypeOptDefaultPath do
          use Dagger.Mod.Object, name: "TypeOptDoc"

          defn should_fail(v: {Dagger.String.t(), default_path: 1}) :: String.t() do
            v
          end
        end
      end

      assert_raise FunctionClauseError, fn ->
        defmodule TypeOptIgnore do
          use Dagger.Mod.Object, name: "TypeOptDoc"

          defn should_fail(v: {Dagger.String.t(), ignore: 1}) :: String.t() do
            v
          end
        end
      end
    end
  end

  test "get_module_doc/1" do
    assert Dagger.Mod.Object.get_module_doc(DocModule) == "The module documentation."
    assert is_nil(Dagger.Mod.Object.get_module_doc(NoDocModule))
    assert is_nil(Dagger.Mod.Object.get_module_doc(HiddenDocModule))
  end

  test "get_function_doc/2" do
    assert Dagger.Mod.Object.get_function_doc(DocModule, :echo) == "Echo the output."
    assert is_nil(Dagger.Mod.Object.get_function_doc(DocModule, :no_fun_doc))
    assert is_nil(Dagger.Mod.Object.get_function_doc(DocModule, :hidden_fun_doc))
  end

  describe "field/3" do
    test "store fields to a module" do
      assert ObjectField.__object__(:fields) == [
               name: %FieldDef{type: :string, doc: nil}
             ]

      assert ObjectFieldOptional.__object__(:fields) == [
               name: %FieldDef{type: {:optional, :string}, doc: nil}
             ]
    end

    test "required fields" do
      assert struct_keys(%ObjectField{name: "value"}) == [:name]
    end

    test "optional fields" do
      assert struct_keys(%ObjectFieldOptional{}) == [:name]
    end

    test "mixes optional and required fields" do
      assert struct_keys(%ObjectFieldMixesOptionalAndRequired{key: "value"}) == [:name, :key]
    end
  end

  test "mixes object struct and function" do
    assert ObjectFiedAndFunction.__object__(:functions) == [
             with_name: %FunctionDef{
               self: false,
               args: [
                 name: [
                   {:ignore, nil},
                   {:deprecated, nil},
                   {:default_path, nil},
                   {:default, nil},
                   {:doc, nil},
                   {:type, :string}
                 ]
               ],
               return: ObjectFieldAndFunction
             },
             fan_out: %Dagger.Mod.Object.FunctionDef{
               self: false,
               args: [
                 name: [
                   ignore: nil,
                   deprecated: nil,
                   default_path: nil,
                   default: nil,
                   doc: nil,
                   type: :string
                 ]
               ],
               return: {:list, ObjectFieldAndFunction}
             }
           ]
  end

  describe "Deprecation level" do
    test "field deprecation" do
      assert DeprecatedDirective.__object__(:fields) == [
               f1: %FieldDef{type: :string, doc: nil, deprecated: "deprecated field"},
               f2: %FieldDef{type: :string, doc: nil, deprecated: nil}
             ]
    end

    test "function argument deprecation" do
      assert DeprecatedDirective.__object__(:functions)[:deprecated_args] ==
               %Dagger.Mod.Object.FunctionDef{
                 self: false,
                 args: [
                   foo: [
                     {:ignore, nil},
                     {:doc, nil},
                     {:default, nil},
                     {:default_path, nil},
                     {:type, :string},
                     {:deprecated, "deprecated argument"}
                   ],
                   bar: [
                     {:ignore, nil},
                     {:doc, nil},
                     {:default, nil},
                     {:default_path, nil},
                     {:type, :string},
                     {:deprecated, nil}
                   ]
                 ],
                 return: :string
               }
    end
  end

  defp struct_keys(struct), do: struct |> Map.from_struct() |> Map.keys()
end

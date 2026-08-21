defmodule PrimitiveTypeArgs do
  @moduledoc false
  use Dagger.Mod.Object, name: "PrimitiveTypeArgs"

  defn accept_string(name: String.t()) :: String.t() do
    "Hello, #{name}"
  end

  defn accept_string2(name: binary()) :: binary() do
    "Hello, #{name}"
  end

  defn accept_integer(value: integer()) :: integer() do
    value
  end

  defn accept_float(value: float()) :: float() do
    value
  end

  defn accept_boolean(name: boolean()) :: String.t() do
    "Hello, #{name}"
  end
end

defmodule PrimitiveTypeDefaultArgs do
  @moduledoc false
  use Dagger.Mod.Object, name: "PrimitiveTypeDefaultArgs"

  defn accept_default_string(name: {String.t(), default: "Foo"}) :: String.t() do
    "Hello #{name}"
  end

  defn accept_default_integer(value: {integer(), default: 42}) :: integer() do
    value
  end

  defn accept_default_float(value: {float(), default: 1.6180342}) :: float() do
    value
  end

  defn accept_default_boolean(value: {boolean(), default: false}) :: boolean() do
    value
  end
end

defmodule EmptyArgs do
  @moduledoc false
  use Dagger.Mod.Object, name: "EmptyArgs"

  defn empty_args() :: String.t() do
    "Empty args"
  end
end

defmodule ObjectArgAndReturn do
  @moduledoc false
  use Dagger.Mod.Object, name: "ObjectArgAndReturn"

  defn accept_and_return_module(container: Dagger.Container.t()) :: Dagger.Container.t() do
    container
  end
end

defmodule ListArgs do
  @moduledoc false
  use Dagger.Mod.Object, name: "ListArg"

  defn accept_list(alist: list(String.t())) :: String.t() do
    Enum.join(alist, ",")
  end

  defn accept_list2(alist: [String.t()]) :: String.t() do
    Enum.join(alist, ",")
  end
end

defmodule OptionalArgs do
  @moduledoc false
  use Dagger.Mod.Object, name: "OptionalArgs"

  defn optional_arg(s: String.t() | nil) :: String.t() do
    "Hello, #{s}"
  end
end

defmodule ArgOptions do
  @moduledoc false
  use Dagger.Mod.Object, name: "ArgOptions"

  defn type_option(
         dir:
           {Dagger.Directory.t() | nil,
            doc: "The directory to run on.",
            default_path: "/sdk/elixir",
            ignore: ["deps", "_build"]}
       ) :: String.t() do
    Dagger.Directory.id(dir)
  end
end

defmodule DeprecatedDirective do
  @moduledoc deprecated: "module deprecation reason"
  use Dagger.Mod.Object, name: "DeprecatedDirective"

  object do
    field(:f1, String.t(), deprecated: "deprecated field")
    field(:f2, String.t(), deprecated: nil)
  end

  @deprecated "deprecation reason"
  defn deprecated_by_attr() :: Dagger.Void.t() do
    :ok
  end

  @doc deprecated: "docstring deprecation reason"
  defn deprecated_by_docstr() :: Dagger.Void.t() do
    :ok
  end

  defn deprecated_args(
         foo: {
           String.t(),
           deprecated: "deprecated argument"
         },
         bar: {
           String.t(),
           deprecated: nil
         }
       ) :: String.t() do
    foo <> bar
  end
end

defmodule CacheOption do
  @moduledoc false
  use Dagger.Mod.Object, name: "CacheOption"

  defn default_cached() :: Dagger.Void.t(), cache: :default do
    :ok
  end

  defn never_cached() :: Dagger.Void.t(), cache: :never do
    :ok
  end

  defn per_session_cached() :: Dagger.Void.t(), cache: :per_session do
    :ok
  end

  defn ttl_cached() :: Dagger.Void.t(), cache: {:ttl, "42s"} do
    :ok
  end

  defn uncached() :: Dagger.Void.t() do
    :ok
  end
end

defmodule CheckOption do
  @moduledoc false
  use Dagger.Mod.Object, name: "CheckOption"

  defn checked_function() :: Dagger.Void.t(), :check do
    :ok
  end

  defn unchecked_function() :: Dagger.Void.t() do
    :ok
  end
end

defmodule GenerateOption do
  @moduledoc false
  use Dagger.Mod.Object, name: "GenerateOption"

  defn generator_function() :: Dagger.Changeset.t(), :generate do
    dag() |> Dagger.Client.changeset()
  end

  # Optional arguments are fine; only *required* ones break the contract.
  defn generator_with_optional_arg(name: {String.t(), default: "gen"}) ::
         Dagger.Changeset.t(),
       :generate do
    _ = name
    dag() |> Dagger.Client.changeset()
  end
end

defmodule UpOption do
  @moduledoc false
  use Dagger.Mod.Object, name: "UpOption"

  defn up_service() :: Dagger.Service.t(), :up do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("nginx")
    |> Dagger.Container.as_service()
  end

  defn plain_service() :: Dagger.Service.t() do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("nginx")
    |> Dagger.Container.as_service()
  end
end

defmodule AgentOption do
  @moduledoc false
  use Dagger.Mod.Object, name: "AgentOption"

  defn agent_function(base: Dagger.LLM.t()) :: Dagger.LLM.t(), :agent do
    Dagger.LLM.with_prompt(base, "be helpful")
  end

  # The base is the one required argument; the rest may be left out.
  defn agent_with_optional_arg(base: Dagger.LLM.t(), prompt: {String.t(), default: "be helpful"}) ::
         Dagger.LLM.t(),
       :agent do
    Dagger.LLM.with_prompt(base, prompt)
  end
end

# The signatures `:check` and `:generate` accept. The rejected ones cannot
# live here: they raise while this file compiles, so they are declared inline
# in the test instead.
defmodule FlagSignatures do
  @moduledoc false
  use Dagger.Mod.Object, name: "FlagSignatures"

  object do
  end

  # `self` is the object, not something the caller supplies.
  defn check_with_self(_self) :: Dagger.Void.t(), :check do
    :ok
  end

  defn generate_with_self(_self) :: Dagger.Changeset.t(), :generate do
    dag() |> Dagger.Client.changeset()
  end

  # The engine fills these in, so none of them is required.
  defn check_with_default(name: {String.t(), default: "check"}) :: Dagger.Void.t(), :check do
    _ = name
    :ok
  end

  defn check_with_default_path(dir: {Dagger.Directory.t(), default_path: "/"}) ::
         Dagger.Void.t(),
       :check do
    _ = dir
    :ok
  end

  defn check_with_optional(name: String.t() | nil) :: Dagger.Void.t(), :check do
    _ = name
    :ok
  end

  defn generate_with_default_path(dir: {Dagger.Directory.t(), default_path: "/"}) ::
         Dagger.Changeset.t(),
       :generate do
    _ = dir
    dag() |> Dagger.Client.changeset()
  end

  defn up_with_self(_self) :: Dagger.Service.t(), :up do
    dag() |> Dagger.Client.container() |> Dagger.Container.as_service()
  end

  defn up_with_default(image: {String.t(), default: "nginx"}) :: Dagger.Service.t(), :up do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from(image)
    |> Dagger.Container.as_service()
  end

  defn agent_with_self(_self, base: Dagger.LLM.t()) :: Dagger.LLM.t(), :agent do
    base
  end

  defn agent_with_optional(base: Dagger.LLM.t(), prompt: String.t() | nil) ::
         Dagger.LLM.t(),
       :agent do
    _ = prompt
    base
  end
end

defmodule CombinedOptions do
  @moduledoc false
  use Dagger.Mod.Object, name: "CombinedOptions"

  defn everything() :: Dagger.Changeset.t(),
       [:check, :generate, cache: {:ttl, "1h30m"}] do
    dag() |> Dagger.Client.changeset()
  end
end

defmodule ReturnVoid do
  @moduledoc false
  use Dagger.Mod.Object, name: "ReturnVoid"

  defn return_void() :: Dagger.Void.t() do
    :ok
  end
end

defmodule SelfObject do
  @moduledoc false
  use Dagger.Mod.Object, name: "SelfObject"

  object do
  end

  defn only_self_arg(_self) :: Dagger.Void.t() do
    :ok
  end

  defn mix_self_and_args(_self, name: String.t()) :: Dagger.Void.t() do
    name
  end
end

defmodule ConstructorFunction do
  @moduledoc false
  use Dagger.Mod.Object, name: "ConstructorFunction"

  object do
    field(:name, String.t())
  end

  defn init(name: String.t()) :: ConstructorFunction.t() do
    %__MODULE__{name: name}
  end
end

defmodule AcceptAndReturnScalar do
  @moduledoc false

  use Dagger.Mod.Object, name: "AcceptAndReturnScalar"

  defn accept(value: Dagger.Platform.t()) :: Dagger.Platform.t() do
    value
  end
end

defmodule AcceptAndReturnEnum do
  @moduledoc false

  use Dagger.Mod.Object, name: "AcceptAndReturnEnum"

  defn accept(value: Dagger.NetworkProtocol.t()) :: Dagger.NetworkProtocol.t() do
    value
  end
end

defmodule Deps.C do
  @moduledoc false

  use Dagger.Mod.Object, name: "C"

  object do
  end

  defn hello() :: String.t() do
    "Hello"
  end
end

defmodule Deps.B do
  @moduledoc false

  use Dagger.Mod.Object, name: "B"

  object do
  end

  defn hello() :: String.t() do
    "Hello"
  end
end

defmodule Deps.A do
  @moduledoc false

  use Dagger.Mod.Object, name: "A"

  object do
  end

  defn do_b() :: Deps.B.t() do
    %Deps.B{}
  end

  defn do_c() :: Deps.C.t() do
    %Deps.B{}
  end
end

defmodule Deps do
  @moduledoc false

  use Dagger.Mod.Object, name: "Deps"

  object do
  end

  defn do_a() :: Deps.A.t() do
    %Deps.A{}
  end
end

defmodule CustomEnum do
  @moduledoc false

  use Dagger.Mod.Object, name: "CustomEnum"

  defn scan(severity: SimpleEnum.t()) :: SimpleEnum.t() do
    severity
  end

  defn enum_opt(opt: EnumWithOption.t()) :: Dagger.Void.t() do
    _ = opt
    :ok
  end
end

defmodule EnumReturnChild do
  @moduledoc false

  use Dagger.Mod.Object, name: "EnumReturnChild"

  object do
  end
end

defmodule EnumOnObjectReturn do
  @moduledoc false

  use Dagger.Mod.Object, name: "EnumOnObjectReturn"

  object do
  end

  defn child_with_enum(status: SimpleEnum.t()) :: EnumReturnChild.t() do
    _ = status
    %EnumReturnChild{}
  end
end

defmodule DocObjects.Child do
  @moduledoc """
  The child object documentation.
  """

  use Dagger.Mod.Object, name: "DocObjectsChild"

  object do
  end

  defn hello() :: String.t() do
    "Hello"
  end
end

defmodule DocObjects do
  @moduledoc """
  The root object documentation.
  """

  use Dagger.Mod.Object, name: "DocObjects"

  object do
  end

  defn child() :: DocObjects.Child.t() do
    %DocObjects.Child{}
  end
end

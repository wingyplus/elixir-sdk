defmodule Errors do
  @moduledoc """
  Every way a module function can fail, so that the error each one reaches the
  caller with can be asserted on.
  """

  use Dagger.Mod.Object, name: "Errors"

  alias Dagger.Client
  alias Dagger.Container
  alias Dagger.Core.ExecError

  @failing_command ["sh", "-c", "echo to-stdout; echo to-stderr >&2; exit 3"]

  @doc "Return an error tuple, the way a function reports a failure it expected."
  defn return_error() :: String.t() do
    {:error, "cannot find the potato"}
  end

  @doc "Raise, the way a function fails on something it did not expect."
  defn raise_error() :: String.t() do
    raise "the potato exploded"
  end

  @doc "Fail on an API error, so that its extensions have to survive the boundary."
  defn exec_error() :: String.t() do
    dag()
    |> failing_container()
    |> Container.stdout()
  end

  @doc "Throw, the way a function fails outside the exception mechanism."
  defn throw_error() :: String.t() do
    throw(:no_potato)
  end

  @doc """
  Report the details an `ExecError` carries, so that a caller can tell whether
  the extensions of a failed exec arrived intact.
  """
  defn exec_error_details() :: String.t() do
    {:error, %ExecError{} = error} = dag() |> failing_container() |> Container.stdout()

    Enum.join(
      [
        "cmd=#{Enum.join(error.cmd, " ")}",
        "exitCode=#{error.exit_code}",
        "stdout=#{String.trim(error.stdout)}",
        "stderr=#{String.trim(error.stderr)}"
      ],
      " "
    )
  end

  defp failing_container(dag) do
    dag
    |> Client.container()
    |> Container.from("alpine:3.22")
    |> Container.with_exec(@failing_command)
  end
end

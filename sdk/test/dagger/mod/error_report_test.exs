defmodule Dagger.Mod.ErrorReportTest do
  use ExUnit.Case, async: true

  alias Dagger.Core.ExecError
  alias Dagger.Core.GraphQL.Response
  alias Dagger.Mod.ErrorReport

  describe "describe/3" do
    test "an exception reports its type, message and stacktrace" do
      {exception, stacktrace} = raise_and_catch(fn -> raise "boom" end)

      assert {message, values} = ErrorReport.describe(:error, exception, stacktrace)
      assert message == "RuntimeError: boom"
      assert values["exception.type"] == "RuntimeError"
      assert values["exception.message"] == "boom"
      assert values["exception.stacktrace"] =~ "error_report_test.exs"
    end

    test "a returned error has no stacktrace to report" do
      assert ErrorReport.describe(:error, "cannot find the potato") ==
               {"cannot find the potato", %{}}

      assert ErrorReport.describe(:error, :enoent) == {"enoent", %{}}
    end

    test "any other returned term is inspected" do
      assert ErrorReport.describe(:error, {:badarg, [1, 2]}) == {"{:badarg, [1, 2]}", %{}}
    end

    test "an API error carries its extensions through" do
      error = %Response.Error{
        message: "no such file",
        path: ["container", "file", "contents"],
        extensions: %{"_type" => "GRAPHQL_ERROR", "code" => 42}
      }

      assert {message, values} = ErrorReport.describe(:error, error)
      assert message == "input: container.file.contents no such file"
      assert values["exception.type"] == "Dagger.Core.GraphQL.Response.Error"
      assert values["_type"] == "GRAPHQL_ERROR"
      assert values["code"] == 42
    end

    test "an exec error carries the extensions of the API error behind it" do
      extensions = %{
        "_type" => "EXEC_ERROR",
        "cmd" => ["sh", "-c", "exit 3"],
        "exitCode" => 3,
        "stdout" => "",
        "stderr" => "boom"
      }

      error =
        extensions
        |> ExecError.from_map()
        |> ExecError.with_original_error(%Response.Error{
          message: "process did not complete successfully",
          path: ["container", "stdout"],
          extensions: extensions
        })

      assert {message, values} = ErrorReport.describe(:error, error)
      assert message == "input: container.stdout process did not complete successfully"
      assert values["exception.type"] == "Dagger.Core.ExecError"
      assert values["cmd"] == ["sh", "-c", "exit 3"]
      assert values["exitCode"] == 3
      assert values["stderr"] == "boom"
    end

    test "a throw or an exit is reported by its kind" do
      assert {message, values} = ErrorReport.describe(:throw, :nope, [])
      assert message == "** (throw) :nope"
      assert values["exception.type"] == "throw"
      assert values["exception.message"] == ":nope"

      assert {"** (exit) shutdown", %{"exception.type" => "exit"}} =
               ErrorReport.describe(:exit, :shutdown, [])
    end

    test "an exception whose message/1 fails is still described" do
      # `ExecError.message/1` delegates to an original error that is not there.
      assert {message, values} = ErrorReport.describe(:error, %ExecError{exit_code: 1})
      assert message =~ "Dagger.Core.ExecError"
      assert values["exception.type"] == "Dagger.Core.ExecError"
    end
  end

  describe "encode_value/1" do
    test "encodes a JSON representable value" do
      assert ErrorReport.encode_value(["sh", "-c"]) == ~s(["sh","-c"])
      assert ErrorReport.encode_value(3) == "3"
      assert ErrorReport.encode_value("boom") == ~s("boom")
    end

    test "falls back to the inspected form of a value it cannot encode" do
      assert ErrorReport.encode_value({:a, :b}) == ~s("{:a, :b}")
      assert ErrorReport.encode_value(self()) =~ "#PID<"
    end
  end

  defp raise_and_catch(fun) do
    fun.()
  rescue
    exception -> {exception, __STACKTRACE__}
  end
end

defmodule Dagger.Mod.EncoderTest do
  use Dagger.DagCase

  alias Dagger.Mod.Encoder

  describe "validate_and_encode/2" do
    test "encode primitive type" do
      assert {:ok, "\"hello\""} = Encoder.validate_and_encode("hello", :string)
      assert {:ok, "1"} = Encoder.validate_and_encode(1, :integer)
      assert {:ok, "2.0"} = Encoder.validate_and_encode(2.0, :float)
      assert {:ok, "true"} = Encoder.validate_and_encode(true, :boolean)
      assert {:ok, "false"} = Encoder.validate_and_encode(false, :boolean)
    end

    test "encode list" do
      assert {:ok, "[1,2,3]"} = Encoder.validate_and_encode([1, 2, 3], {:list, :integer})
    end

    test "encode idable module", %{dag: dag} do
      assert {:ok, id} =
               Encoder.validate_and_encode(Dagger.Client.container(dag), Dagger.Container)

      assert is_binary(id)
    end

    test "encode void type" do
      assert {:ok, "null"} = Encoder.validate_and_encode("hello", Dagger.Void)
      assert {:ok, "null"} = Encoder.validate_and_encode(1, Dagger.Void)
      assert {:ok, "null"} = Encoder.validate_and_encode(:ok, Dagger.Void)
    end

    test "encode object" do
      assert {:ok, "{\"name\":\"john\"}"} =
               Encoder.validate_and_encode(%ObjectField{name: "john"}, ObjectField)
    end

    test "encode enum" do
      # The engine looks a returned member up by its name, which is its key.
      assert {:ok, "\"unknown\""} = Encoder.validate_and_encode(:unknown, SimpleEnum)
      assert {:ok, "\"UNKNOWN\""} = Encoder.validate_and_encode(:UNKNOWN, EnumAliasValue)
      assert {:ok, "\"TCP\""} = Encoder.validate_and_encode(:TCP, Dagger.NetworkProtocol)
    end

    test "encode enum error" do
      assert {:error, %Dagger.Mod.TypeMismatchError{}} =
               Encoder.validate_and_encode(:nope, EnumAliasValue)
    end

    test "encode error" do
      assert {:error, _} = Encoder.validate_and_encode(1, :string)
    end
  end
end

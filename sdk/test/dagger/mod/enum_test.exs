defmodule Dagger.Mod.EnumTest do
  use ExUnit.Case, async: true

  test "get value description" do
    assert Dagger.Mod.Enum.get_key_description(SimpleEnum, :high) == nil
    assert Dagger.Mod.Enum.get_key_description(EnumWithOption, :unknown) == "Unknown severity"
    assert Dagger.Mod.Enum.get_key_description(EnumAliasValue, :LOW) == "Low severity"
  end

  test "get possible values" do
    assert SimpleEnum.__enum__(:keys) == [:unknown, :low, :high]
  end

  test "get value of the enum" do
    assert_enum = fn module ->
      assert Enum.map([:unknown, :low, :high], &module.__enum__(:value, &1)) == [
               "unknown",
               "low",
               "high"
             ]
    end

    assert_enum.(SimpleEnum)
    assert_enum.(EnumWithOption)
  end

  test "get value deprecation reason" do
    assert Dagger.Mod.Enum.get_key_deprecated(SimpleEnum, :high) == nil
    assert Dagger.Mod.Enum.get_key_deprecated(EnumAliasValue, :UNKNOWN) == nil
    assert Dagger.Mod.Enum.get_key_deprecated(EnumWithDeprecatedMember, :high) == nil

    assert Dagger.Mod.Enum.get_key_deprecated(EnumWithDeprecatedMember, :low) ==
             "Use `high` instead."

    assert Dagger.Mod.Enum.get_key_deprecated(EnumWithDeprecatedMember, :medium) ==
             "Use `high` instead."
  end

  test "a codegen enum has no deprecated member" do
    assert Dagger.Mod.Enum.get_key_deprecated(Dagger.NetworkProtocol, :TCP) == nil
  end

  test "alias key with value" do
    assert EnumAliasValue.__enum__(:value, :UNKNOWN) == "unknown"
    assert EnumAliasValue.__enum__(:value, :LOW) == "low"
  end
end

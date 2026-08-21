defmodule Dagger.Mod.Object.Defn do
  @moduledoc false

  @doc false
  def define(name, args, return, block) do
    typespec_args =
      case args do
        {_self, args} ->
          [quote(do: t()) | Enum.map(args, &typespec_arg/1)]

        args ->
          Enum.map(args, &typespec_arg/1)
      end

    args =
      case args do
        {self, args} ->
          [self_var(self) | Enum.map(args, &def_arg/1)]

        args ->
          Enum.map(args, &def_arg/1)
      end

    quote do
      @spec unquote(name)(unquote_splicing(typespec_args)) :: unquote(return)
      def unquote(name)(unquote_splicing(args)) do
        unquote(block)
      end
    end
  end

  # An argument as it appears in the function head. An argument that declares a
  # `:default` takes it as its Elixir default, and an argument typed as optional
  # takes `nil`, so an Elixir caller can leave out whatever the engine can.

  # {var, {type, opts}}
  defp def_arg({name, {type, opts}}) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :default) -> with_default(name, opts[:default])
      optional?(type) -> with_default(name, nil)
      true -> Macro.var(name, nil)
    end
  end

  # {var, type}
  defp def_arg({name, type}) do
    if optional?(type) do
      with_default(name, nil)
    else
      Macro.var(name, nil)
    end
  end

  defp optional?({:|, _, [_type, nil]}), do: true
  defp optional?(_type), do: false

  defp with_default(name, default) do
    {:\\, [], [Macro.var(name, nil), default]}
  end

  # var
  defp self_var({name, _, nil}) do
    Macro.var(name, nil)
  end

  # A typespec never carries a default, so an argument is named here and only
  # given its default in the function head.
  defp typespec_arg({name, {type, opts}}) when is_list(opts) do
    typespec_arg({name, type})
  end

  defp typespec_arg({name, type}) do
    quote do
      unquote(Macro.var(name, nil)) :: unquote(type)
    end
  end
end

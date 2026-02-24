defmodule Axiom.Checker.Error do
  @moduledoc """
  Represents a static type checking error found by the checker.
  """

  defstruct [:message, :position]

  @type t :: %__MODULE__{
          message: String.t(),
          position: non_neg_integer() | nil
        }
end

defmodule Axiom.StaticError do
  @moduledoc """
  Exception raised when the static type checker finds errors.
  """

  defexception [:message, :errors]

  @type t :: %__MODULE__{
          message: String.t(),
          errors: [Axiom.Checker.Error.t()]
        }

  @impl true
  def exception(errors) when is_list(errors) do
    msg =
      errors
      |> Enum.map(fn
        %Axiom.Checker.Error{position: nil, message: m} ->
          "  - #{m}"

        %Axiom.Checker.Error{position: pos, message: m} ->
          "  - at word #{pos + 1}: #{m}"
      end)
      |> Enum.join("\n")

    %__MODULE__{message: "Static type errors:\n#{msg}", errors: errors}
  end

  def exception(msg) when is_binary(msg) do
    %__MODULE__{message: msg, errors: []}
  end
end

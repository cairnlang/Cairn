defmodule Axiom.Types do
  @moduledoc """
  Type definitions for the Axiom language.
  """

  @type axiom_type :: :int | :float | :bool | {:list, axiom_type} | :any

  @type token_type ::
          :int_lit
          | :float_lit
          | :bool_lit
          | :list_open
          | :list_close
          | :op
          | :ident
          | :fn_def
          | :fn_end
          | :post
          | :colon
          | :type
          | :arrow
          | :if_kw
          | :else_kw

  @type token :: {token_type, term(), non_neg_integer()}

  defmodule Node do
    @moduledoc """
    A node in the Axiom DAG.
    """
    defstruct [:hash, :op, :inputs, :type, :meta]

    @type t :: %__MODULE__{
            hash: String.t(),
            op: atom(),
            inputs: [String.t()],
            type: Axiom.Types.axiom_type() | nil,
            meta: map()
          }
  end

  defmodule Function do
    @moduledoc """
    An Axiom function definition.
    """
    defstruct [:name, :param_types, :return_type, :body, :post_condition]

    @type t :: %__MODULE__{
            name: String.t(),
            param_types: [Axiom.Types.axiom_type()],
            return_type: Axiom.Types.axiom_type(),
            body: [Axiom.Types.token()],
            post_condition: [Axiom.Types.token()] | nil
          }
  end
end

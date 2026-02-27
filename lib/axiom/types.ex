defmodule Axiom.Types do
  @moduledoc """
  Type definitions for the Axiom language.
  """

  @type axiom_type ::
          :int
          | :float
          | :bool
          | {:list, axiom_type}
          | {:map, axiom_type, axiom_type}
          | {:pid, axiom_type}
          | {:monitor, axiom_type}
          | {:block, term()}
          | {:user_type, String.t()}
          | :any
          | :void
          | :str

  @type token_type ::
          :int_lit
          | :float_lit
          | :bool_lit
          | :list_open
          | :list_close
          | :map_open
          | :map_lit
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
          | :import_kw
          | :type_kw
          | :protocol_kw
          | :using_kw
          | :recv_kw
          | :match_kw
          | :receive_kw
          | :spawn_kw
          | :spawn_link_kw
          | :pipe
          | :equals
          | :constructor

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

  defmodule TypeDef do
    @moduledoc """
    A sum type (tagged union) definition.
    """
    defstruct [:name, :variants]

    @type t :: %__MODULE__{
            name: String.t(),
            variants: %{String.t() => [Axiom.Types.axiom_type()]}
          }
  end

  defmodule Function do
    @moduledoc """
    An Axiom function definition.
    """
    defstruct [:name, :param_types, :return_types, :body, :pre_condition, :post_condition]

    @type t :: %__MODULE__{
            name: String.t(),
            param_types: [Axiom.Types.axiom_type()],
            return_types: [Axiom.Types.axiom_type()],
            body: [Axiom.Types.token()],
            pre_condition: [Axiom.Types.token()] | nil,
            post_condition: [Axiom.Types.token()] | nil
          }
  end

  defmodule ProtocolDef do
    @moduledoc """
    A finite checker-only protocol definition.
    """
    defstruct [:name, :steps]

    @type step :: {:send, String.t()} | {:recv, String.t()}

    @type t :: %__MODULE__{
            name: String.t(),
            steps: [step()]
          }
  end
end

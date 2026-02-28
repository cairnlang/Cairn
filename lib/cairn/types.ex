defmodule Cairn.Types do
  @moduledoc """
  Type definitions for the Cairn language.
  """

  @type cairn_type ::
          :int
          | :float
          | :bool
          | {:list, cairn_type}
          | {:map, cairn_type, cairn_type}
          | {:pid, cairn_type}
          | {:monitor, cairn_type}
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
    A node in the Cairn DAG.
    """
    defstruct [:hash, :op, :inputs, :type, :meta]

    @type t :: %__MODULE__{
            hash: String.t(),
            op: atom(),
            inputs: [String.t()],
            type: Cairn.Types.cairn_type() | nil,
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
            variants: %{String.t() => [Cairn.Types.cairn_type()]}
          }
  end

  defmodule Function do
    @moduledoc """
    An Cairn function definition.
    """
    defstruct [:name, :param_types, :return_types, :body, :pre_condition, :post_condition]

    @type t :: %__MODULE__{
            name: String.t(),
            param_types: [Cairn.Types.cairn_type()],
            return_types: [Cairn.Types.cairn_type()],
            body: [Cairn.Types.token()],
            pre_condition: [Cairn.Types.token()] | nil,
            post_condition: [Cairn.Types.token()] | nil
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

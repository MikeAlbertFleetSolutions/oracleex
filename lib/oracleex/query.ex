defmodule Oracleex.Query do
  @moduledoc """
  Implementation of `DBConnection.Query` for `Oracleex`.

  The structure is:
    * `name` - currently not used.
    * `statement` - SQL statement to run using `:odbc`.
  """

  @type t :: %__MODULE__{
    name: iodata,
    statement: iodata,
    columns: [String.t] | nil
  }

  defstruct [:name, :statement, :columns]
end

defimpl DBConnection.Query, for: Oracleex.Query do
  alias Oracleex.Query
  alias Oracleex.Result
  alias Oracleex.Type

  @spec parse(query :: Query.t(), opts :: Keyword.t()) :: Query.t()
  def parse(query, _opts), do: query

  @spec describe(query :: Query.t(), opts :: Keyword.t()) :: Query.t()
  def describe(query, _opts), do: query

  @spec encode(query :: Query.t(),
    params :: [Type.param()], opts :: Keyword.t()) :: [Type.param()]
  def encode(_query, params, opts) do
    Enum.map(params, &(Type.encode(&1, opts)))
  end

  @spec decode(query :: Query.t(), result :: Result.t(), opts :: Keyword.t()) ::
    Result.t()
  def decode(_query, %Result{rows: rows} = result, opts) when not is_nil(rows) do
    Map.put(result, :rows, Enum.map(rows, fn row -> Enum.map(row, &(Type.decode(&1, opts))) end))
  end
  def decode(_query, result, _opts), do: result
end

defimpl String.Chars, for: Oracleex.Query do
  def to_string(%Oracleex.Query{statement: statement}) do
    IO.iodata_to_binary(statement)
  end
end

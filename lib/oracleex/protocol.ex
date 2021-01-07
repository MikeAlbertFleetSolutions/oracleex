defmodule Oracleex.Protocol do
  @moduledoc """
  Implementation of `DBConnection` behaviour for `Oracleex.ODBC`.

  Handles translation of concepts to what ODBC expects and holds
  state for a connection.

  This module is not called directly, but rather through
  other `Oracleex` modules or `DBConnection` functions.
  """

  use DBConnection

  alias Oracleex.ODBC
  alias Oracleex.Result

  defstruct [pid: nil, oracle: :idle, conn_opts: []]

  @typedoc """
  Process state.

  Includes:

  * `:pid`: the pid of the ODBC process
  * `:oracle`: the transaction state. Can be `:idle` (not in a transaction),
      `:transaction` (in a transaction) or `:auto_commit` (connection in
      autocommit mode)
  * `:conn_opts`: the options used to set up the connection.
  """
  @type state :: %__MODULE__{pid: pid(),
                             oracle: :idle | :transaction | :auto_commit,
                             conn_opts: Keyword.t}

  @type query :: Oracleex.Query.t
  @type params :: [{:odbc.odbc_data_type(), :odbc.value()}]
  @type result :: Result.t
  @type cursor :: any
  @type status :: :idle | :transaction | :error

  @doc false
  @spec connect(opts :: Keyword.t) :: {:ok, state}
                                    | {:error, Exception.t}
  def connect(opts) do

    conn_opts = [
      {"DSN", opts[:dsn] || System.get_env("ORACLE_DSN") || "OracleODBC-12c"},
      {"DBQ", opts[:service] || System.get_env("ORACLE_SERVICE")},
      {"UID", opts[:username] || System.get_env("ORACLE_USR")},
      {"PWD", opts[:password] || System.get_env("ORACLE_PWD")}
    ]
    conn_str = Enum.reduce(conn_opts, "", fn {key, value}, acc ->
      acc <> "#{key}=#{value};" end)

    case ODBC.start_link(conn_str, opts) do
      {:ok, pid} -> {:ok, %__MODULE__{
                        pid: pid,
                        conn_opts: opts,
                        oracle: if(opts[:auto_commit] == :on,
                          do: :auto_commit,
                          else: :idle)
                     }}
      response -> response
    end
  end

  @doc false
  @spec disconnect(err :: Exception.t, state) :: :ok
  def disconnect(_err, %{pid: pid} = state) do
    case ODBC.disconnect(pid) do
      :ok -> :ok
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc false
  @spec reconnect(new_opts :: Keyword.t, state) :: {:ok, state}
  def reconnect(new_opts, state) do
    with :ok <- disconnect("Reconnecting", state),
      do: connect(new_opts)
  end

  @doc false
  @spec checkout(state) :: {:ok, state}
                         | {:disconnect, Exception.t, state}
  def checkout(state) do
    {:ok, state}
  end

  @doc false
  @spec checkin(state) :: {:ok, state}
                        | {:disconnect, Exception.t, state}
  def checkin(state) do
    {:ok, state}
  end

  @doc false
  @spec handle_begin(opts :: Keyword.t, state) ::
    {:ok, result, state}
  | {:error | :disconnect, Exception.t, state}
  def handle_begin(opts, state) do
    case Keyword.get(opts, :mode, :transaction) do
      :transaction -> handle_transaction(:begin, opts, state)
      :savepoint -> handle_savepoint(:begin, opts, state)
    end
  end

  @doc false
  @spec handle_commit(opts :: Keyword.t, state) ::
    {:ok, result, state} |
    {:error | :disconnect, Exception.t, state}
  def handle_commit(opts, state) do
    case Keyword.get(opts, :mode, :transaction) do
      :transaction -> handle_transaction(:commit, opts, state)
      :savepoint -> handle_savepoint(:commit, opts, state)
    end
  end

  @doc false
  @spec handle_rollback(opts :: Keyword.t, state) ::
    {:ok, result, state} |
    {:error | :disconnect, Exception.t, state}
  def handle_rollback(opts, state) do
    case Keyword.get(opts, :mode, :transaction) do
      :transaction -> handle_transaction(:rollback, opts, state)
      :savepoint -> handle_savepoint(:rollback, opts, state)
    end
  end

  defp handle_transaction(:begin, _opts, state) do
    case state.oracle do
      :idle -> {:ok, %Result{num_rows: 0}, %{state | oracle: :transaction}}
      :transaction -> {:error, state}
      :auto_commit -> {:error, state}
    end
  end
  defp handle_transaction(:commit, _opts, state) do
    case ODBC.commit(state.pid) do
      :ok -> {:ok, %Result{}, %{state | oracle: :idle}}
      {:error, reason} -> {:error, %{state | oracle: :error}}
    end
  end
  defp handle_transaction(:rollback, _opts, state) do
    case ODBC.rollback(state.pid) do
      :ok -> {:ok, %Result{}, %{state | oracle: :idle}}
      {:error, reason} -> {:disconnect, DBConnection.TransactionError.exception(reason), %{state | oracle: :error}}
    end
  end

  defp handle_savepoint(:begin, opts, state) do
    if state.oracle == :autocommit do
      {:error,
       %Oracleex.Error{message: "savepoint not allowed in autocommit mode"},
       state}
    else
      handle_execute(
        %Oracleex.Query{name: "", statement: "SAVEPOINT Oracleex_savepoint"},
        [], opts, state)
    end
  end
  defp handle_savepoint(:commit, _opts, state) do
    {:ok, %Result{}, state}
  end
  defp handle_savepoint(:rollback, opts, state) do
    handle_execute(
      %Oracleex.Query{name: "", statement: "ROLLBACK TO Oracleex_savepoint"},
      [], opts, state)
  end

  @doc false
  @spec handle_prepare(query, opts :: Keyword.t, state) ::
    {:ok, query, state} |
    {:error | :disconnect, Exception.t, state}
  def handle_prepare(query, _opts, state) do
    {:ok, query, state}
  end

  @doc false
  @spec handle_execute(query, params, opts :: Keyword.t, state) ::
    {:ok, query, result, state} |
    {:error | :disconnect, Exception.t, state}
  def handle_execute(query, params, opts, state) do
    with {:ok, message, new_state} <- do_query(query, params, opts, state)
    do
      case new_state.oracle do
        :idle ->
          with {:ok, _, post_commit_state} <- handle_commit(opts, new_state)
          do
            {:ok, query, message, post_commit_state}
          end
        :transaction -> {:ok, query, message, new_state}
        :auto_commit ->
          with {:ok, post_connect_state} <- switch_auto_commit(:off, new_state)
          do
            {:ok, query, message, post_connect_state}
          end
      end
    else
      {status, message, new_state} -> {status, message, new_state}
    end
  end

  defp do_query(query, params, opts, state) do
    case ODBC.query(state.pid, query.statement, params, opts) do
      {:error,
        %Oracleex.Error{odbc_code: :not_allowed_in_transaction} = reason} ->
        if state.oracle == :auto_commit do
          {:error, reason, state}
        else
          with {:ok, new_state} <- switch_auto_commit(:on, state),
            do: handle_execute(query, params, opts, new_state)
        end
      {:error,
        %Oracleex.Error{odbc_code: :connection_exception} = reason} ->
        {:disconnect, reason, state}
      {:error, reason} ->
        {:error, reason, state}
      {:selected, columns, rows} ->
        {:ok, %Result{columns: Enum.map(columns, &(to_string(&1))), rows: rows, num_rows: Enum.count(rows)}, state}
      {:updated, num_rows} ->
        {:ok, %Result{num_rows: num_rows}, state}
    end
  end

  defp switch_auto_commit(new_value, state) do
    reconnect(Keyword.put(state.conn_opts, :auto_commit, new_value), state)
  end

  @doc false
  @spec handle_close(query, opts :: Keyword.t, state) ::
    {:ok, result, state} |
    {:error | :disconnect, Exception.t, state}
  def handle_close(_query, _opts, state) do
    {:ok, %Result{}, state}
  end

  def ping(state) do
    query = %Oracleex.Query{name: "ping", statement: "SELECT 1 FROM DUAL"}
    case do_query(query, [], [], state) do
      {:ok, _, new_state} -> {:ok, new_state}
      {:error, reason, new_state} -> {:disconnect, reason, new_state}
      other -> other
    end
  end

  @doc false
  @spec handle_status(opts :: Keyword.t(), state :: any()) ::
    {status(), new_state :: any()} |
    {:disconnect, Exception.t(), new_state :: any()}
  def handle_status(_opts, state) do
    status = status_state(state)
    {status, state}
  end

  defp status_state(state) do
    case state.oracle do
      :idle -> :idle
      :transaction -> :transaction
      :auto_commit -> :error
      :error -> :error
    end
  end

  # TODO: mark not implemented
  # handle_deallocate
  # handle_declare
  # handle_fetch

end

defmodule Oracleex.TransactionTest do
  use ExUnit.Case, async: true

  alias Oracleex.Result

  setup_all do
    {:ok, pid} = Oracleex.start_link([dsn: "OracleODBC-19", service: "db", username: "web_ca", password: "bitsandbobs", scrollable_cursors: :off])
    {:ok, [pid: pid]}
  end

  test "simple transaction test", %{pid: pid} do
    table_name = "web_ca.simple"

    {:ok, _, _} = Oracleex.query(pid,
      "create table #{table_name} (name varchar(50));", [])

    assert {:ok, %Result{}} = DBConnection.transaction(pid, fn pid ->
      {:ok, _, result} = Oracleex.query(pid,
        "insert into #{table_name} values ('Steven');", [])
      result
    end)

    assert {:ok, _query, %Result{columns: ["NAME"], rows: [["Steven"]]}} =
      Oracleex.query(pid, "select * from #{table_name};", [])

    Oracleex.query(pid, "drop table #{table_name}", [])
  end

  test "nested transaction test", %{pid: pid} do
    table_name = "web_ca.nested"

    Oracleex.query!(pid, "CREATE TABLE #{table_name} (name varchar(50));", [])

    assert {:ok, %Result{}} = DBConnection.transaction(pid, fn pid ->
      {:ok, _} = DBConnection.transaction(pid, fn pid ->
        {:ok, _, result} = Oracleex.query(pid,
          "insert into #{table_name} values ('Steven');", [])
        result
      end)
      {:ok, result} = DBConnection.transaction(pid, fn pid ->
        {:ok, _, result} = Oracleex.query(pid,
          "insert into #{table_name} values ('Tim');", [])
        result
      end)
      result
    end)

    assert {:ok, _query, %Result{columns: ["NAME"],
      rows: [["Steven"], ["Tim"]]}} = Oracleex.query(pid,
      "select * from #{table_name};", [])

    Oracleex.query(pid, "drop table #{table_name}", [])
  end

  test "failing transaction test", %{pid: pid} do
    table_name = "web_ca.failing"

    Oracleex.query!(pid,
      "create table #{table_name} (name varchar(3));", [])

    assert_raise Oracleex.Error, fn ->
      DBConnection.transaction(pid, fn pid ->
        {:ok, _} = DBConnection.transaction(pid, fn pid ->
          Oracleex.query!(pid,
            "insert into #{table_name} values ('Tim');", [])
        end)
        {:ok, result} = DBConnection.transaction(pid, fn pid ->
          Oracleex.query!(pid,
            "insert into #{table_name} values ('Steven');", [])
        end)
        result
      end)
    end

    assert {:ok, _, %Result{num_rows: 0}} =
      Oracleex.query(pid, "select * from #{table_name};", [])

    Oracleex.query(pid, "drop table #{table_name}", [])
  end

  # Revisit this test if we think we need to; I'm not sure whether it is covered here or in ecto.
  # test "failing transaction test - #2", %{pid: pid} do
  #   table_name = "web_ca.failing"

  #   Oracleex.query(pid, "drop table #{table_name}", [])

  #   Oracleex.query!(pid,
  #     "create table #{table_name} (name varchar(3));", [])

  #   asdf =
  #     DBConnection.transaction(pid, fn pid ->
  #         Oracleex.query(pid,
  #           "insert into #{table_name} values ('Tim');", [])
  #         Oracleex.query(pid,
  #           "insert into #{table_name} values ('Steven');", [])
  #     end)

  #   IO.inspect asdf

  #   assert {:ok, _, %Result{num_rows: 0}} =
  #     Oracleex.query(pid, "select * from #{table_name};", [])

  #   Oracleex.query(pid, "drop table #{table_name}", [])
  # end

  test "manual rollback transaction test", %{pid: pid} do
    table_name = "web_ca.roll_back"

    Oracleex.query!(pid,
      "create table #{table_name} (name varchar(3));", [])

    assert {:error, :rollback} =
      DBConnection.transaction(pid, fn pid ->
        with {:ok, _result} <- DBConnection.transaction(pid, fn pid ->
          with {:ok, _, _result} <-
                Oracleex.query(pid,
                  "insert into #{table_name} values ('Tim');", [])
            do
              assert {:ok, _, %Result{num_rows: 1}} =
                Oracleex.query(pid, "select * from #{table_name};", [])

            else
              {:error, reason} -> reason # never get here DBConnection.rollback(pid, reason)
          end
        end)
        do
          DBConnection.rollback(pid, :rollback)
        end
      end)

    assert {:ok, _, %Result{num_rows: 0}} =
      Oracleex.query(pid, "select * from #{table_name};", [])

    Oracleex.query(pid, "drop table #{table_name}", [])
  end

  test "explicit rollback of failed insert", %{pid: pid} do
    table_name = "web_ca.roll_back_again"
    Oracleex.query(pid, "drop table #{table_name}", [])

    Oracleex.query!(pid,
      "create table #{table_name} (name varchar(3));", [])

    assert {:error, %Oracleex.Error{}} = DBConnection.transaction(pid, fn pid ->
      with {:ok, _, result} <-
        Oracleex.query(pid,
          "insert into #{table_name} values ('Steven');", [])
        do
          result
        else
          {:error, reason} -> DBConnection.rollback(pid, reason)
      end
    end)

    assert {:ok, _, %Result{num_rows: 0}} =
      Oracleex.query(pid, "select * from #{table_name};", [])

    Oracleex.query(pid, "drop table #{table_name}", [])
  end

  test "manual rollback transaction test - complex", %{pid: pid} do
    table_name = "web_ca.roll_back_complex"

    Oracleex.query!(pid,
      "create table #{table_name} (name varchar(3));", [])

    assert {:error, :rollback} =
      DBConnection.transaction(pid, fn pid ->
        with {:ok, _} <- DBConnection.transaction(pid, fn pid ->
          with {:ok, _, result} <-
                Oracleex.query(pid,
                  "insert into #{table_name} values ('Steven');", [])
            do
              result
            else
              {:error, reason} -> DBConnection.rollback(pid, reason)
          end
        end),
        {:ok, result} <- DBConnection.transaction(pid, fn pid ->
          with {:ok, _, result} <-
                Oracleex.query(pid,
                  "insert into #{table_name} values ('Tim');", [])
            do
              result
            else
              {:error, reason} -> DBConnection.rollback(pid, reason)
          end
        end)
        do
          result
        end
      end)

    assert {:ok, _, %Result{num_rows: 0}} =
      Oracleex.query(pid, "select * from #{table_name};", [])

    Oracleex.query(pid, "drop table #{table_name}", [])
  end

end

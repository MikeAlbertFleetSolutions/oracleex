defmodule Oracleex.ConstraintsTest do
  use ExUnit.Case, async: true

  setup_all do
    {:ok, pid} = Oracleex.start_link([])
    Oracleex.query!(pid, "DROP DATABASE IF EXISTS constraints_test;", [])
    {:ok, _, _} = Oracleex.query(pid, "CREATE DATABASE constraints_test;", [])

    {:ok, [pid: pid]}
  end

  test "Unique constraint", %{pid: pid} do
    table_name = "constraints_test.dbo.uniq"
    Oracleex.query!(pid, """
      CREATE TABLE #{table_name}
      (id int CONSTRAINT id_unique UNIQUE)
    """, [])
    Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?)", [42])
    error = assert_raise Oracleex.Error, fn ->
      Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?)", [42])
    end
    assert error.constraint_violations == [unique: "id_unique"]
  end

  test "Unique index", %{pid: pid} do
    table_name = "constraints_test.dbo.uniq_ix"
    Oracleex.query!(pid, """
    CREATE TABLE #{table_name} (id int);
    CREATE UNIQUE INDEX id_unique ON #{table_name} (id);
    """, [])
    Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?)", [42])
    error = assert_raise Oracleex.Error, fn ->
      Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?)", [42])
    end
    assert error.constraint_violations == [unique: "id_unique"]
  end

  test "Foreign Key constraint", %{pid: pid} do
    assoc_table_name = "constraints_test.dbo.assoc"
    table_name = "constraints_test.dbo.fk"
    Oracleex.query!(pid, """
    CREATE TABLE #{assoc_table_name}
    (id int CONSTRAINT id_pk PRIMARY KEY)
    """, [])
    Oracleex.query!(pid, """
    CREATE TABLE #{table_name}
    (id int CONSTRAINT id_foreign FOREIGN KEY REFERENCES #{assoc_table_name})
    """, [])
    Oracleex.query!(pid, "INSERT INTO #{assoc_table_name} VALUES (?)", [42])
    error = assert_raise Oracleex.Error, fn ->
      Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?)", [12])
    end
    assert error.constraint_violations == [foreign_key: "id_foreign"]
  end

  test "Check constraint", %{pid: pid} do
    table_name = "constraints_test.dbo.chk"
    Oracleex.query!(pid, """
    CREATE TABLE #{table_name}
    (id int CONSTRAINT id_check CHECK (id = 1))
    """, [])
    error = assert_raise Oracleex.Error, fn ->
      Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?)", [42])
    end
    assert error.constraint_violations == [check: "id_check"]
  end

  @tag skip: "Database doesn't support this"
  test "Multiple constraints", %{pid: pid} do
    table_name = "constraints_test.dbo.mult"
    Oracleex.query!(pid, """
    CREATE TABLE #{table_name}
    (id int CONSTRAINT id_unique UNIQUE,
     foo int CONSTRAINT foo_check CHECK (foo = 3))
    """, [])
    Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?, ?)", [42, 3])
    error = assert_raise Oracleex.Error, fn ->
      Oracleex.query!(pid, "INSERT INTO #{table_name} VALUES (?, ?)", [42, 5])
    end
    assert error.constraint_violations == [unique: "id_unique", check: "foo_check"]
  end

end

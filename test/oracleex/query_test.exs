defmodule Oracleex.QueryTest do
  use ExUnit.Case, async: true

  alias Oracleex.Result

  setup_all do
    {:ok, pid} = Oracleex.start_link([dsn: "OracleODBC-12c", service: "db", username: "web_ca", password: "bitsandbobs", scrollable_cursors: :off])
    Oracleex.query(pid, "drop table web_ca.simple_select", [])
    Oracleex.query(pid, "drop table web_ca.parametrized_query", [])

    {:ok, [pid: pid]}
  end

  test "simple select", %{pid: pid} do
    assert {:ok, _, %Result{}} = Oracleex.query(pid,
      "create table web_ca.simple_select (name varchar(50))", [])

    assert {:ok, _, %Result{num_rows: 1}} = Oracleex.query(pid,
      ["insert into web_ca.simple_select values ('Steven')"], [])

    assert {:ok, _, %Result{columns: ["NAME"], num_rows: 1, rows: [["Steven"]]}}
      = Oracleex.query(pid, "select * from web_ca.simple_select", [])
  end

  test "parametrized queries", %{pid: pid} do
    assert {:ok, _, %Result{}} = Oracleex.query(pid,
      "create table web_ca.parametrized_query" <>
      "(id number(19, 0), name varchar(50), joined timestamp)", [])

    assert {:ok, _, %Result{num_rows: 1}} = Oracleex.query(pid,
      ["insert into web_ca.parametrized_query values (?, ?, to_timestamp(?, 'YYYY-MM-DD HH24:MI:SS.FF'))"],
      [1, "Tim", "2001-06-11 08:14:00.742000000"])

    assert {:ok, _, %Result{
               columns: ["ID", "NAME", "JOINED"],
               num_rows: 1,
               rows: [["1", "Tim", _]]}} =
      Oracleex.query(pid, "select * from web_ca.parametrized_query", [])
  end
end

defmodule Oracleex.TypesTest do
  use ExUnit.Case, async: true

  alias Oracleex.Result

  setup_all do
    {:ok, pid} = Oracleex.start_link([scrollable_cursors: :off])

    {:ok, [pid: pid]}
  end

  test "char", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [["Nathan"]]}} =
      act(pid, "char(6)", ["Nathan"])
  end

  test "nchar", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [["e→øæ"]]}} =
      act(pid, "nchar(4)", ["e→øæ"])
  end

  test "nchar with preserved encoding", %{pid: pid} do
    expected = :unicode.characters_to_binary("e→ø",
      :unicode, {:utf16, :little})
    assert {_query, %Result{columns: ["TEST"], rows: [[^expected]]}} =
      act(pid, "nchar(3)", ["e→ø"], [preserve_encoding: true])
  end

  test "varchar", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [["Nathan"]]}} =
      act(pid, "varchar(6)", ["Nathan"])
  end

  test "nvarchar with unicode characters", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [["Nathan Molnár"]]}} =
      act(pid, "nvarchar2(30)", ["Nathan Molnár"])
  end

  test "nvarchar", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [["e→øæ"]]}} =
      act(pid, "nvarchar2(4)", ["e→øæ"])
  end

  test "nvarchar with preserved encoding", %{pid: pid} do
    expected = :unicode.characters_to_binary("e→ø",
      :unicode, {:utf16, :little})
    assert {_query, %Result{columns: ["TEST"], rows: [[^expected]]}} =
      act(pid, "nvarchar2(3)", ["e→ø"], [preserve_encoding: true])
  end

  test "numeric(9, 0) as integer", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [[123456789]]}} =
      act(pid, "numeric(9)", [123456789])
  end

  test "numeric(8, 0) as decimal", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [[12345678]]}} =
      act(pid, "numeric(8)", [Decimal.new(12345678)])
  end

  test "numeric(15, 0) as decimal", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [[123456789012345]]}} =
      act(pid, "numeric(15)", [Decimal.new(123456789012345)])
  end

  test "numeric(38, 0) as decimal", %{pid: pid} do
    number = "12345678901234567890123456789012345678"
    assert {_query, %Result{columns: ["TEST"], rows: [[^number]]}} =
      act(pid, "numeric(38)", [Decimal.new(number)])
  end

  test "numeric(36, 0) as string", %{pid: pid} do
    number = "123456789012345678901234567890123456"
    assert {_query, %Result{columns: ["TEST"], rows: [[^number]]}} =
      act(pid, "numeric(36)", [number])
  end

  test "numeric(5, 2) as decimal", %{pid: pid} do
    number = Decimal.new("123.45")
    assert {_query, %Result{columns: ["TEST"], rows: [[value]]}} =
      act(pid, "numeric(5,2)", [number])
    assert Decimal.equal?(number, value)
  end

  test "numeric(6, 3) as float", %{pid: pid} do
    number = Decimal.new("123.456")
    assert {_query, %Result{columns: ["TEST"], rows: [[value]]}} =
      act(pid, "numeric(6,3)", [123.456])
    assert Decimal.equal?(number, value)
  end

  test "real as decimal", %{pid: pid} do
    number = Decimal.new("123.45")
    assert {_query, %Result{columns: ["TEST"], rows: [[%Decimal{} = value]]}} =
      act(pid, "real", [number])
    assert Decimal.equal?(number, Decimal.round(value, 2))
  end

  test "float as decimal", %{pid: pid} do
    number = Decimal.new("123.45")
    assert {_query, %Result{columns: ["TEST"], rows: [[%Decimal{} = value]]}} =
      act(pid, "float", [number])
    assert Decimal.equal?(number, Decimal.round(value, 2))
  end

  test "double as decimal", %{pid: pid} do
    number = Decimal.new("1.12345678901234")
    assert {_query, %Result{columns: ["TEST"], rows: [[%Decimal{} = value]]}} =
      act(pid, "double precision", [number])
    assert Decimal.equal?(number, value)
  end

  test "timestamp as tuple", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"],
      rows: [[{{2017, 1, 1}, {12, 10, 0}}]]}} = act(pid, "timestamp",
      [{{2017, 1, 1}, {12, 10, 0, 0}}])
  end

  test "date as tuple", %{pid: pid} do
    assert {_query, %Result{columns: ["TEST"], rows: [[{{2017, 1, 1}, {0, 0, 0}}]]}} =
      act(pid, "date", [{2017, 1, 1}])
  end

  test "null", %{pid: pid} do
    type = "char(13)"

    Oracleex.query(pid, "drop table #{table_name(type)}", [])
    Oracleex.query!(pid,
      "create table #{table_name(type)} (test #{type}, num number)", [])
    Oracleex.query!(pid,
      "insert into #{table_name(type)} (num) values (?)", [2])

    assert {_query, %Result{rows: [[nil]]}} =
      Oracleex.query!(pid,
        "select to_number(test) from #{table_name(type)}", [])

    Oracleex.query(pid, "drop table #{table_name(type)}", [])
  end

  test "invalid input type", %{pid: pid} do
    assert_raise Oracleex.Error, ~r/unrecognised type/, fn ->
      act(pid, "char(10)", [{"Nathan"}])
    end
  end

  test "invalid input binary", %{pid: pid} do
    assert_raise Oracleex.Error, ~r/failed to convert/, fn ->
      act(pid, "char(12)", [<<110, 0, 200>>])
    end
  end

  defp table_name(type) do
    ~s(web_ca."#{Base.url_encode64 type}")
  end
  defp act(pid, type, params, opts \\ []) do
    Oracleex.query(pid, "drop table #{table_name(type)}", [])

    Oracleex.query!(pid,
      "create table #{table_name(type)} (test #{type})", [], opts)
    Oracleex.query!(pid,
      "insert into #{table_name(type)} values (?)", params, opts)
    result = Oracleex.query!(pid,
      "select * from #{table_name(type)}", [], opts)

    Oracleex.query(pid, "drop table #{table_name(type)}", [])
    result
  end
end

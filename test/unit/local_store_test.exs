defmodule DistDb.StoreLocalTest do
  use ExUnit.Case, async: false
  doctest DistDb.Store

  setup do
    DistDb.Store.clear()
    :ok
  end

  describe "basic local operations (no replication)" do
    test "put and get a value" do
      assert :ok = DistDb.Store.put("name", "alice")
      assert "alice" = DistDb.Store.get("name")
    end

    test "get returns nil for non-existent key" do
      assert nil == DistDb.Store.get("nonexistent")
    end

    test "put updates existing value" do
      assert :ok = DistDb.Store.put("counter", 1)
      assert 1 = DistDb.Store.get("counter")

      assert :ok = DistDb.Store.put("counter", 2)
      assert 2 = DistDb.Store.get("counter")
    end

    test "delete removes a key" do
      assert :ok = DistDb.Store.put("temp", "value")
      assert "value" = DistDb.Store.get("temp")

      assert :ok = DistDb.Store.delete("temp")
      assert nil == DistDb.Store.get("temp")
    end

    test "delete is idempotent" do
      assert :ok = DistDb.Store.delete("nonexistent")
      assert :ok = DistDb.Store.delete("nonexistent")
    end

    test "list_all returns empty map initially" do
      assert %{} = DistDb.Store.list_all()
    end

    test "list_all returns all key-value pairs" do
      assert :ok = DistDb.Store.put("key1", "value1")
      assert :ok = DistDb.Store.put("key2", "value2")
      assert :ok = DistDb.Store.put("key3", "value3")

      all = DistDb.Store.list_all()
      assert %{"key1" => "value1", "key2" => "value2", "key3" => "value3"} = all
    end

    test "list_all reflects deletions" do
      assert :ok = DistDb.Store.put("key1", "value1")
      assert :ok = DistDb.Store.put("key2", "value2")
      assert :ok = DistDb.Store.delete("key1")

      all = DistDb.Store.list_all()
      assert %{"key2" => "value2"} = all
      refute Map.has_key?(all, "key1")
    end

    test "supports various value types" do
      assert :ok = DistDb.Store.put("string", "text")
      assert :ok = DistDb.Store.put("number", 42)
      assert :ok = DistDb.Store.put("list", [1, 2, 3])
      assert :ok = DistDb.Store.put("map", %{nested: "value"})

      assert "text" = DistDb.Store.get("string")
      assert 42 = DistDb.Store.get("number")
      assert [1, 2, 3] = DistDb.Store.get("list")
      assert %{nested: "value"} = DistDb.Store.get("map")
    end
  end
end

defmodule Symphony.AgentProfileRegistryTest do
  use ExUnit.Case, async: true

  alias Symphony.{AgentProfileRegistry, Config}

  setup do
    dir = Path.join(System.tmp_dir!(), "symphony-agents-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    config = %Config{workspace_root: dir, agent_profiles_path: Path.join(dir, "profiles.json")}
    name = :"agent_registry_#{System.unique_integer([:positive])}"
    {:ok, pid} = AgentProfileRegistry.start_link(name: name, config: config)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, server: pid, config: config}
  end

  test "creates, lists, updates, deletes, and persists profiles", %{
    server: server,
    config: config
  } do
    assert {:ok, profile} =
             AgentProfileRegistry.create(
               %{"name" => "Violin Builder", "role" => "developer", "section" => "Strings"},
               server
             )

    assert profile["id"] == "violin-builder"
    assert profile["instrument_name"] == "Violin"
    assert {:ok, [listed]} = AgentProfileRegistry.list(server)
    assert listed["name"] == "Violin Builder"

    assert {:ok, updated} =
             AgentProfileRegistry.update(
               profile["id"],
               %{"section" => "Brass", "instrument_name" => "Trumpet"},
               server
             )

    assert updated["section"] == "Brass"
    assert updated["instrument_name"] == "Trumpet"

    name2 = :"agent_registry_reload_#{System.unique_integer([:positive])}"
    {:ok, reloaded} = AgentProfileRegistry.start_link(name: name2, config: config)
    assert {:ok, persisted} = AgentProfileRegistry.get(profile["id"], reloaded)
    assert persisted["section"] == "Brass"

    assert :ok = AgentProfileRegistry.delete(profile["id"], server)
    assert {:ok, []} = AgentProfileRegistry.list(server)
  end

  test "validates required names and duplicate names", %{server: server} do
    assert {:error, {:validation, _}} = AgentProfileRegistry.create(%{"name" => ""}, server)
    assert {:ok, _} = AgentProfileRegistry.create(%{"name" => "Piano Reviewer"}, server)

    assert {:error, {:conflict, _}} =
             AgentProfileRegistry.create(%{"name" => "piano reviewer"}, server)
  end

  test "blank id is treated as generated id and persists", %{server: server, config: config} do
    assert {:ok, profile} =
             AgentProfileRegistry.create(%{"id" => "", "name" => "Cello Builder"}, server)

    assert profile["id"] == "cello-builder"
    assert {:ok, meta} = AgentProfileRegistry.metadata(server)
    assert meta.count == 1
    assert meta.exists
    assert meta.writable
    assert File.exists?(meta.path)

    name2 = Module.concat(__MODULE__, BlankReloadedRegistry)
    {:ok, reloaded} = AgentProfileRegistry.start_link(name: name2, config: config)
    assert {:ok, persisted} = AgentProfileRegistry.get("cello-builder", reloaded)
    assert persisted["name"] == "Cello Builder"
  end
end

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
    assert profile["stage_position"] == %{"section" => "strings", "seat" => "front-center"}
    assert profile["music"]["motif"] == "Violin entrance"
    assert profile["music"]["dynamic"] == "mezzo-piano"
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

  test "normalizes explicit stage placement and music references", %{server: server} do
    assert {:ok, profile} =
             AgentProfileRegistry.create(
               %{
                 "name" => "Horn Refiner",
                 "role" => "Refiner",
                 "section" => "Brass",
                 "instrument_name" => "French Horn",
                 "stage_position" => %{"section" => "brass", "seat" => "back-right"},
                 "music" => %{"motif" => "Refiner ostinato", "dynamic" => "forte"}
               },
               server
             )

    assert profile["stage_position"] == %{"section" => "brass", "seat" => "back-right"}
    assert profile["music"]["motif"] == "Refiner ostinato"
    assert profile["music"]["dynamic"] == "forte"
    assert profile["music"]["register"] == "lower-middle"
  end

  test "reload_config switches storage path and reloads profiles", %{
    server: server,
    config: config
  } do
    assert {:ok, _profile} = AgentProfileRegistry.create(%{"name" => "Original Violin"}, server)

    new_path = Path.join(Path.dirname(config.agent_profiles_path), "reloaded-profiles.json")

    File.write!(
      new_path,
      Jason.encode!(%{
        "profiles" => [
          %{
            "id" => "reload-judge",
            "name" => "Reload Judge",
            "role" => "Judge",
            "section" => "Piano",
            "instrument_name" => "Piano"
          }
        ]
      })
    )

    assert {:ok, meta} =
             AgentProfileRegistry.reload_config(%{config | agent_profiles_path: new_path}, server)

    assert meta.path == new_path
    assert meta.count == 1
    assert {:error, :not_found} = AgentProfileRegistry.get("original-violin", server)
    assert {:ok, profile} = AgentProfileRegistry.get("reload-judge", server)
    assert profile["instrument_name"] == "Piano"
  end

  test "ensure_many creates workflow profiles while preserving operator stage and music edits", %{
    server: server
  } do
    profiles = [
      %{
        "id" => "workflow-judge",
        "name" => "Workflow Judge",
        "role" => "Judge",
        "profile_key" => "workflow-judge",
        "section" => "Piano",
        "instrument_name" => "Piano",
        "capabilities" => ["review", "quality-gates"],
        "music" => %{"motif" => "Movement II / Judge"}
      },
      %{
        "id" => "workflow-refiner",
        "name" => "Workflow Refiner",
        "role" => "Refiner",
        "profile_key" => "workflow-refiner",
        "section" => "Brass",
        "instrument_name" => "French Horn",
        "capabilities" => ["refinement"]
      }
    ]

    assert {:ok, created} = AgentProfileRegistry.ensure_many(profiles, server)
    assert created.created == ["workflow-judge", "workflow-refiner"]
    assert created.updated == []
    assert Enum.map(created.profiles, & &1["id"]) == ["workflow-judge", "workflow-refiner"]

    assert {:ok, _edited} =
             AgentProfileRegistry.update(
               "workflow-judge",
               %{
                 "section" => "Bells",
                 "instrument_name" => "Glockenspiel",
                 "music" => %{"motif" => "Operator cue", "dynamic" => "forte"},
                 "stage_position" => %{"section" => "bells", "seat" => "back-center"}
               },
               server
             )

    assert {:ok, refreshed} =
             AgentProfileRegistry.ensure_many(
               [
                 %{
                   "id" => "workflow-judge",
                   "name" => "Workflow Judge",
                   "role" => "Judge",
                   "section" => "Piano",
                   "instrument_name" => "Concert Grand",
                   "capabilities" => ["review", "safety"]
                 }
               ],
               server
             )

    assert refreshed.created == []
    assert refreshed.updated == ["workflow-judge"]
    assert {:ok, [judge, refiner]} = AgentProfileRegistry.list(server)
    assert refiner["id"] == "workflow-refiner"
    assert judge["section"] == "Bells"
    assert judge["instrument_name"] == "Glockenspiel"
    assert judge["music"]["motif"] == "Operator cue"
    assert judge["music"]["dynamic"] == "forte"
    assert judge["music"]["register"] == "high"
    assert judge["stage_position"] == %{"section" => "bells", "seat" => "back-center"}
    assert judge["capabilities"] == ["review", "safety"]
    assert refiner["stage_position"] == %{"section" => "brass", "seat" => "mid-right"}
  end
end

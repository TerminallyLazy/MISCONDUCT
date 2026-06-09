defmodule Symphony.AgentProfileRegistry do
  use GenServer

  @default_sections ["Strings", "Woodwinds", "Brass", "Percussion", "Piano", "Bells"]
  @default_instruments %{
    "Strings" => "Violin",
    "Woodwinds" => "Clarinet",
    "Brass" => "French Horn",
    "Percussion" => "Timpani",
    "Piano" => "Piano",
    "Bells" => "Glockenspiel"
  }

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  def list(server \\ __MODULE__), do: GenServer.call(server, :list)
  def metadata(server \\ __MODULE__), do: GenServer.call(server, :metadata)
  def get(id, server \\ __MODULE__), do: GenServer.call(server, {:get, id})
  def create(attrs, server \\ __MODULE__), do: GenServer.call(server, {:create, attrs})
  def ensure(attrs, server \\ __MODULE__), do: GenServer.call(server, {:ensure, attrs})
  def ensure_many(attrs, server \\ __MODULE__), do: GenServer.call(server, {:ensure_many, attrs})
  def update(id, attrs, server \\ __MODULE__), do: GenServer.call(server, {:update, id, attrs})
  def delete(id, server \\ __MODULE__), do: GenServer.call(server, {:delete, id})

  @impl true
  def init(config) do
    path = profile_path(config)
    File.mkdir_p!(Path.dirname(path))
    {:ok, %{path: path, profiles: load_profiles(path)}}
  end

  @impl true
  def handle_call(:list, _from, state),
    do: {:reply, {:ok, Map.values(state.profiles) |> Enum.sort_by(& &1["name"])}, state}

  def handle_call(:metadata, _from, state) do
    {:reply,
     {:ok,
      %{
        path: state.path,
        count: map_size(state.profiles),
        exists: File.exists?(state.path),
        writable: writable?(state.path)
      }}, state}
  end

  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.profiles, id) do
      {:ok, profile} -> {:reply, {:ok, profile}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:create, attrs}, _from, state) do
    with {:ok, profile} <- normalize(attrs, nil),
         :ok <- unique_name(profile, state.profiles, nil),
         :ok <- unique_id(profile["id"], state.profiles, nil) do
      next = put_persisted(state, profile)
      {:reply, {:ok, profile}, next}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ensure, attrs}, _from, state) do
    case ensure_profiles([attrs], state) do
      {:ok, result, next} -> {:reply, {:ok, hd(result.profiles)}, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ensure_many, attrs}, _from, state) when is_list(attrs) do
    case ensure_profiles(attrs, state) do
      {:ok, result, next} -> {:reply, {:ok, result}, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ensure_many, _attrs}, _from, state),
    do: {:reply, {:error, {:validation, "profiles must be a list"}}, state}

  def handle_call({:update, id, attrs}, _from, state) do
    case Map.fetch(state.profiles, id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, current} ->
        with {:ok, profile} <- normalize(Map.merge(current, stringify(attrs)), id),
             :ok <- unique_name(profile, state.profiles, id),
             :ok <- unique_id(profile["id"], state.profiles, id) do
          next = delete_persisted(state, id) |> put_persisted(profile)
          {:reply, {:ok, profile}, next}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:delete, id}, _from, state) do
    if Map.has_key?(state.profiles, id) do
      {:reply, :ok, delete_persisted(state, id)}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  defp profile_path(config) do
    config.agent_profiles_path ||
      Path.join(config.workspace_root || System.tmp_dir!(), "agent_profiles.json")
  end

  defp load_profiles(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> Jason.decode!()
        |> case do
          %{"profiles" => profiles} when is_list(profiles) -> profiles
          profiles when is_list(profiles) -> profiles
          _ -> []
        end
        |> Enum.reduce(%{}, fn raw, acc ->
          case normalize(raw, raw["id"]) do
            {:ok, p} -> Map.put(acc, p["id"], p)
            _ -> acc
          end
        end)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp persist!(state) do
    payload =
      Jason.encode!(%{"profiles" => Map.values(state.profiles) |> Enum.sort_by(& &1["name"])},
        pretty: true
      )

    tmp = state.path <> ".tmp"
    File.write!(tmp, payload)
    File.rename!(tmp, state.path)
    state
  end

  defp put_persisted(state, profile),
    do: %{state | profiles: Map.put(state.profiles, profile["id"], profile)} |> persist!()

  defp delete_persisted(state, id),
    do: %{state | profiles: Map.delete(state.profiles, id)} |> persist!()

  defp ensure_profiles(attrs_list, state) do
    attrs_list
    |> Enum.reduce_while({state.profiles, [], []}, fn attrs, {profiles, created, updated} ->
      attrs = stringify(attrs)

      with {:ok, seed} <- normalize(attrs, nil),
           {profile, action} <- ensure_profile(seed["id"], attrs, profiles),
           :ok <-
             unique_name(profile, profiles, if(action == :updated, do: profile["id"], else: nil)),
           :ok <-
             unique_id(
               profile["id"],
               profiles,
               if(action == :updated, do: profile["id"], else: nil)
             ) do
        next_profiles = Map.put(profiles, profile["id"], profile)

        case action do
          :created -> {:cont, {next_profiles, created ++ [profile["id"]], updated}}
          :updated -> {:cont, {next_profiles, created, updated ++ [profile["id"]]}}
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} ->
        {:error, reason}

      {profiles, created, updated} ->
        ensured_ids = created ++ updated

        result = %{
          profiles:
            profiles
            |> Map.take(ensured_ids)
            |> Map.values()
            |> Enum.sort_by(& &1["name"]),
          created: created,
          updated: updated,
          count: length(ensured_ids)
        }

        {:ok, result, %{state | profiles: profiles} |> persist!()}
    end
  end

  defp ensure_profile(id, attrs, profiles) do
    case Map.fetch(profiles, id) do
      {:ok, current} ->
        with {:ok, profile} <- normalize(Map.merge(current, attrs), id) do
          {profile, :updated}
        end

      :error ->
        with {:ok, profile} <- normalize(attrs, nil) do
          {profile, :created}
        end
    end
  end

  defp normalize(attrs, forced_id) when is_map(attrs) do
    attrs = stringify(attrs)
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    name = attrs["name"] |> string_or("") |> String.trim()
    section = attrs["section"] |> string_or("Strings") |> known_section()
    id = blank_nil(forced_id) || blank_nil(attrs["id"]) || slug(name)
    workspace_key = attrs["workspace_key"] || attrs["workspaceKey"] || ""

    cond do
      name == "" ->
        {:error, {:validation, "name is required"}}

      id == "" ->
        {:error, {:validation, "id is required"}}

      not Regex.match?(~r/^[A-Za-z0-9._-]+$/, id) ->
        {:error, {:validation, "id may only contain letters, numbers, dot, underscore, and dash"}}

      workspace_key != "" and not Regex.match?(~r/^[A-Za-z0-9._-]+$/, workspace_key) ->
        {:error,
         {:validation,
          "workspace_key may only contain letters, numbers, dot, underscore, and dash"}}

      true ->
        {:ok,
         %{
           "id" => id,
           "name" => name,
           "role" => attrs["role"] |> string_or("Agent"),
           "profile_key" =>
             attrs["profile_key"] || attrs["profileKey"] || attrs["role"] || "agent",
           "section" => section,
           "instrument_name" =>
             attrs["instrument_name"] || attrs["instrumentName"] || @default_instruments[section],
           "enabled" => bool_or(attrs["enabled"], true),
           "description" => attrs["description"] |> string_or(""),
           "instructions" => attrs["instructions"] |> string_or(""),
           "model" => attrs["model"] |> string_or(""),
           "workspace_key" => workspace_key,
           "capabilities" => list_strings(attrs["capabilities"]),
           "assignment_policy" =>
             policy(attrs["assignment_policy"] || attrs["assignmentPolicy"] || %{}),
           "max_concurrent_tasks" =>
             int_or(attrs["max_concurrent_tasks"] || attrs["maxConcurrentTasks"], 1),
           "status" => if(bool_or(attrs["enabled"], true), do: "idle", else: "disabled"),
           "current_assignments" => [],
           "music" => music(attrs["music"]),
           "stage_position" => stage_position(attrs["stage_position"] || attrs["stagePosition"]),
           "created_at" => attrs["created_at"] || now,
           "updated_at" => now
         }}
    end
  end

  defp normalize(_, _), do: {:error, {:validation, "profile must be an object"}}

  defp music(raw) when is_map(raw), do: stringify(raw)
  defp music(_), do: %{}

  defp stage_position(raw) when is_map(raw), do: stringify(raw)
  defp stage_position(_), do: %{}

  defp policy(raw) when is_map(raw) do
    raw = stringify(raw)

    %{
      "allowed_task_types" => list_strings(raw["allowed_task_types"] || raw["allowedTaskTypes"]),
      "blocked_task_types" => list_strings(raw["blocked_task_types"] || raw["blockedTaskTypes"]),
      "required_labels" => list_strings(raw["required_labels"] || raw["requiredLabels"]),
      "excluded_labels" => list_strings(raw["excluded_labels"] || raw["excludedLabels"]),
      "requires_manual_assignment" =>
        bool_or(raw["requires_manual_assignment"] || raw["requiresManualAssignment"], true),
      "can_take_untriaged" =>
        bool_or(raw["can_take_untriaged"] || raw["canTakeUntriaged"], false),
      "handoff_allowed" => bool_or(raw["handoff_allowed"] || raw["handoffAllowed"], true)
    }
  end

  defp policy(_), do: policy(%{})

  defp unique_name(profile, profiles, current_id) do
    conflict? =
      Enum.any?(profiles, fn {id, p} ->
        id != current_id and String.downcase(p["name"] || "") == String.downcase(profile["name"])
      end)

    if conflict?, do: {:error, {:conflict, "agent name already exists"}}, else: :ok
  end

  defp unique_id(id, profiles, current_id) do
    if Map.has_key?(profiles, id) and id != current_id,
      do: {:error, {:conflict, "agent id already exists"}},
      else: :ok
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]+/, "-")
    |> String.trim("-")
  end

  defp known_section(section) do
    section = string_or(section, "Strings")
    if section in @default_sections, do: section, else: "Strings"
  end

  defp writable?(path) do
    File.mkdir_p!(Path.dirname(path))
    probe = path <> ".write-test"
    File.write!(probe, "ok")
    File.rm(probe)
    true
  rescue
    _ -> false
  end

  defp blank_nil(nil), do: nil
  defp blank_nil(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: v)
  defp blank_nil(v), do: v

  defp string_or(nil, default), do: default
  defp string_or(v, _default), do: to_string(v)
  defp bool_or(v, _default) when is_boolean(v), do: v
  defp bool_or(nil, default), do: default

  defp bool_or(v, default) when is_binary(v),
    do:
      String.downcase(v) in ["true", "1", "yes"] ||
        (default == true and String.downcase(v) not in ["false", "0", "no"])

  defp bool_or(_, default), do: default
  defp int_or(v, _default) when is_integer(v) and v > 0, do: v

  defp int_or(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp int_or(_, default), do: default

  defp list_strings(v) when is_list(v),
    do: v |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp list_strings(v) when is_binary(v),
    do: v |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp list_strings(_), do: []
end

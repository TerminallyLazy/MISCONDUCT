defmodule Symphony.Workflow.Files do
  @moduledoc """
  Safe backend-owned WORKFLOW.md file management.

  The desktop UI is only an HTTP client; this module owns path policy,
  template generation, validation, preview, atomic writes, and moves.
  """

  alias Symphony.{Config, Workflow.Loader}
  alias Symphony.Filesystem.SafePath

  @templates %{
    "blank" => %{
      id: "blank",
      name: "Blank Score",
      description: "Minimal WORKFLOW.md scaffold with unresolved fields clearly marked.",
      tags: ["blank", "scaffold"],
      required_context: [],
      variables: ["name", "objective"]
    },
    "linear_codex_judge_refiner" => %{
      id: "linear_codex_judge_refiner",
      name: "Linear + Codex with Judge/Refiner",
      description:
        "Real Linear issue intake, Codex execution, and explicit generator/judge/refiner metadata.",
      tags: ["linear", "codex", "judge", "refiner"],
      required_context: ["LINEAR_API_KEY", "LINEAR_PROJECT_SLUG"],
      variables: ["name", "objective", "max_concurrent_agents", "poll_interval_ms"]
    },
    "repository_orchestra" => %{
      id: "repository_orchestra",
      name: "Repository Orchestra",
      description:
        "Project-grounded workflow skeleton for repository implementation, review, and validation.",
      tags: ["repository", "orchestra", "validation"],
      required_context: ["project_path"],
      variables: ["name", "objective", "project_path"]
    }
  }

  @companion_profiles %{
    "linear_codex_judge_refiner" => [
      %{
        "id" => "workflow-generator",
        "name" => "Workflow Generator",
        "role" => "Generator",
        "profile_key" => "workflow-generator",
        "section" => "Woodwinds",
        "instrument_name" => "Clarinet",
        "description" => "Opens the score by turning real issue context into bounded plans.",
        "instructions" =>
          "Draft implementation plans using only real Linear issue context and repository facts.",
        "capabilities" => ["workflow-generation", "planning", "linear-intake"],
        "music" => %{
          "motif" => "Overture / Intake",
          "dynamic" => "mezzo-piano",
          "register" => "middle"
        },
        "stage_position" => %{"section" => "woodwinds", "seat" => "front-left"}
      },
      %{
        "id" => "workflow-builder",
        "name" => "Codex Builder",
        "role" => "Builder",
        "profile_key" => "workflow-builder",
        "section" => "Strings",
        "instrument_name" => "Violin",
        "description" => "Carries the implementation line through the active Codex workspace.",
        "instructions" => "Run Codex against real issue workspaces and keep changes scoped.",
        "capabilities" => ["implementation", "codex", "repository-work"],
        "music" => %{
          "motif" => "Movement I / Build",
          "dynamic" => "mezzo-forte",
          "register" => "upper-middle"
        },
        "stage_position" => %{"section" => "strings", "seat" => "front-center"}
      },
      %{
        "id" => "workflow-judge",
        "name" => "Workflow Judge",
        "role" => "Judge",
        "profile_key" => "workflow-judge",
        "section" => "Piano",
        "instrument_name" => "Piano",
        "description" =>
          "Evaluates completed movements against quality, safety, and scope gates.",
        "instructions" =>
          "Judge work against tests, issue fit, changed-file scope, and secret-safety constraints.",
        "capabilities" => ["review", "quality-gates", "safety"],
        "music" => %{
          "motif" => "Movement II / Judge",
          "dynamic" => "mezzo-piano",
          "register" => "middle"
        },
        "stage_position" => %{"section" => "piano", "seat" => "center-right"}
      },
      %{
        "id" => "workflow-refiner",
        "name" => "Workflow Refiner",
        "role" => "Refiner",
        "profile_key" => "workflow-refiner",
        "section" => "Brass",
        "instrument_name" => "French Horn",
        "description" =>
          "Resolves judge findings with bounded, evidence-based correction passes.",
        "instructions" =>
          "Fix judge findings without inventing facts or expanding the task scope.",
        "capabilities" => ["refinement", "review-fixes", "bounded-retry"],
        "music" => %{
          "motif" => "Movement III / Refine",
          "dynamic" => "mezzo-forte",
          "register" => "lower-middle"
        },
        "stage_position" => %{"section" => "brass", "seat" => "back-right"}
      }
    ],
    "repository_orchestra" => [
      %{
        "id" => "repository-workflow-generator",
        "name" => "Repository Planner",
        "role" => "Generator",
        "profile_key" => "repository-workflow-generator",
        "section" => "Woodwinds",
        "instrument_name" => "Clarinet",
        "description" => "Reads repository context and sets the opening implementation theme.",
        "instructions" => "Inspect real repository facts before proposing implementation phases.",
        "capabilities" => ["repository-analysis", "planning", "source-reading"],
        "music" => %{"motif" => "Score Reading", "dynamic" => "piano", "register" => "middle"},
        "stage_position" => %{"section" => "woodwinds", "seat" => "front-left"}
      },
      %{
        "id" => "repository-workflow-builder",
        "name" => "Repository Builder",
        "role" => "Builder",
        "profile_key" => "repository-workflow-builder",
        "section" => "Strings",
        "instrument_name" => "Viola",
        "description" => "Implements scoped repository changes from the selected score.",
        "instructions" => "Make narrow repository changes and preserve unrelated worktree state.",
        "capabilities" => ["implementation", "repository-work", "desktop-app"],
        "music" => %{"motif" => "Composition", "dynamic" => "mezzo-forte", "register" => "middle"},
        "stage_position" => %{"section" => "strings", "seat" => "front-center"}
      },
      %{
        "id" => "repository-workflow-judge",
        "name" => "Repository Judge",
        "role" => "Judge",
        "profile_key" => "repository-workflow-judge",
        "section" => "Piano",
        "instrument_name" => "Piano",
        "description" => "Checks repository evidence, validation, attribution, and safety.",
        "instructions" => "Judge changes using repository-grounded commands and source evidence.",
        "capabilities" => ["review", "validation", "source-attribution"],
        "music" => %{"motif" => "Critique", "dynamic" => "mezzo-piano", "register" => "middle"},
        "stage_position" => %{"section" => "piano", "seat" => "center-right"}
      },
      %{
        "id" => "repository-workflow-validator",
        "name" => "Repository Validator",
        "role" => "Validator",
        "profile_key" => "repository-workflow-validator",
        "section" => "Percussion",
        "instrument_name" => "Timpani",
        "description" => "Marks validation beats and unresolved command gaps.",
        "instructions" => "Run available project validation commands and report exact results.",
        "capabilities" => ["tests", "validation", "command-results"],
        "music" => %{"motif" => "Rehearsal", "dynamic" => "forte", "register" => "low"},
        "stage_position" => %{"section" => "percussion", "seat" => "back-center"}
      },
      %{
        "id" => "repository-workflow-refiner",
        "name" => "Repository Refiner",
        "role" => "Refiner",
        "profile_key" => "repository-workflow-refiner",
        "section" => "Brass",
        "instrument_name" => "French Horn",
        "description" => "Closes review findings with bounded correction passes.",
        "instructions" =>
          "Resolve judge findings while keeping changes inside the requested scope.",
        "capabilities" => ["refinement", "review-fixes", "bounded-retry"],
        "music" => %{
          "motif" => "Performance",
          "dynamic" => "mezzo-forte",
          "register" => "lower-middle"
        },
        "stage_position" => %{"section" => "brass", "seat" => "back-right"}
      }
    ]
  }

  @known_placeholders ~w(issue.identifier issue.title issue.state issue.description attempt workspace.root agent.name workflow.name)
  @required_headings ["Objective", "Inputs", "Agents", "Phases", "Validation Gates", "Guardrails"]

  def templates do
    @templates |> Map.values() |> Enum.sort_by(& &1.name)
  end

  def companion_agent_profiles(template_id) when is_binary(template_id),
    do: companion_agent_profiles(template_id, %{})

  def companion_agent_profiles(attrs) when is_map(attrs) do
    attrs = stringify(attrs || %{})

    cond do
      is_binary(attrs["template_id"]) or is_binary(attrs["template"]) ->
        companion_agent_profiles(
          attrs["template_id"] || attrs["template"],
          attrs["overrides"] || attrs["context"] || %{}
        )

      is_binary(attrs["content"]) ->
        companion_agent_profiles_from_content(attrs["content"])

      true ->
        []
    end
  end

  def companion_agent_profiles(_), do: []

  def companion_agent_profiles(template_id, overrides) when is_binary(template_id) do
    template_id
    |> base_companion_profiles()
    |> apply_profile_overrides(overrides)
  end

  def list(opts \\ []) do
    config = Keyword.get(opts, :config) || current_config()
    root = root(config)
    active = Path.expand(config.workflow_path || Path.join(root, "WORKFLOW.md"))

    workflows =
      root
      |> Path.join("**/WORKFLOW.md")
      |> Path.wildcard()
      |> Enum.reject(&unsafe_existing?/1)
      |> Enum.filter(&SafePath.inside_root?(root, &1))
      |> Enum.take(100)
      |> Enum.map(&summary(&1, root, active))

    {:ok, %{ok: true, root: root, workflows: workflows, templates: templates()}}
  end

  def generate(attrs, opts \\ []) do
    attrs = stringify(attrs || %{})
    template_id = attrs["template_id"] || attrs["template"] || "linear_codex_judge_refiner"
    overrides = stringify(attrs["overrides"] || attrs["context"] || %{})

    with {:ok, content} <- render_template(template_id, overrides),
         {:ok, validation} <- validate(%{"content" => content}, opts) do
      {:ok,
       %{
         ok: true,
         draft_id: "wf_" <> short_hash(content),
         filename: "WORKFLOW.md",
         template_id: template_id,
         content: content,
         validation: validation,
         review: review_content(content, validation),
         provenance: %{generated_at: DateTime.utc_now(), generator: "Symphony.Workflow.Files"}
       }}
    end
  end

  def validate(attrs, opts \\ []) do
    attrs = stringify(attrs || %{})

    with {:ok, content} <- content_from(attrs, opts) do
      result = validation_for(content, opts)
      {:ok, result}
    end
  end

  def preview(attrs, opts \\ []) do
    attrs = stringify(attrs || %{})

    with {:ok, content} <- content_from(attrs, opts),
         {:ok, wf} <- Loader.parse(content),
         {:ok, validation} <- validate(%{"content" => content}, opts) do
      {:ok,
       %{
         ok: true,
         preview: %{
           frontmatter: redact_config(wf.config),
           prompt_template: wf.prompt_template,
           metadata: metadata(wf),
           content_sha256: sha256(content)
         },
         validation: validation,
         review: review_content(content, validation)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def create(attrs, opts \\ []) do
    attrs = stringify(attrs || %{})
    overwrite = bool(attrs["overwrite"], false)

    with {:ok, path} <- resolve_workflow_path(attrs["path"] || "WORKFLOW.md", opts),
         :ok <- conflict(path, overwrite),
         {:ok, content} <- content_from(attrs, opts),
         {:ok, validation} <- validate(%{"content" => content}, opts),
         :ok <- valid_for_write(validation),
         :ok <- atomic_write(path, content) do
      {:ok,
       %{
         ok: true,
         created: true,
         path: rel(path, opts),
         absolute_path: path,
         content_sha256: sha256(content),
         validation: validation,
         restart_required: false,
         reload_required: active_path?(path, opts),
         reload_supported: true
       }}
    end
  end

  def move(attrs, opts \\ []) do
    attrs = stringify(attrs || %{})
    overwrite = bool(attrs["overwrite"], false)

    with {:ok, source} <- resolve_workflow_path(attrs["source_path"] || attrs["from"], opts),
         {:ok, dest} <- resolve_workflow_path(attrs["destination_path"] || attrs["to"], opts),
         :ok <- exists(source),
         :ok <- SafePath.reject_symlink(source),
         :ok <- conflict(dest, overwrite),
         {:ok, validation} <- validate(%{"path" => rel(source, opts)}, opts),
         :ok <- valid_for_write(validation),
         :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.rename(source, dest) do
      {:ok,
       %{
         ok: true,
         moved: true,
         source_path: rel(source, opts),
         destination_path: rel(dest, opts),
         active_workflow_moved: active_path?(source, opts),
         restart_required: false,
         reload_required: active_path?(source, opts) or active_path?(dest, opts),
         reload_supported: true,
         validation: validation
       }}
    else
      {:error, :exdev} -> copy_move(attrs, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def render_template(id, overrides \\ %{}) do
    overrides = stringify(overrides || %{})

    case Map.has_key?(@templates, id) do
      false -> {:error, :template_not_found}
      true -> {:ok, template(id, overrides)}
    end
  end

  defp template("blank", o) do
    name = value(o, "name", "unresolved-workflow")
    objective = value(o, "objective", "TODO: describe the real objective for this workflow.")

    """
    ---
    schema_version: 1
    name: #{yaml(name)}
    description: Blank workflow scaffold with unresolved fields.
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: $LINEAR_PROJECT_SLUG
    polling:
      interval_ms: 30000
    workspace:
      root: ./symphony_workspaces
    agent:
      max_concurrent_agents: 1
      max_turns: 20
      profiles_path: ./agent_profiles.json
    codex:
      command: codex app-server
    server:
      port: 4004
    generator:
      provider: symphony-template
      profile: workflow-generator
      instructions: Create a project-grounded workflow without inventing missing context.
    judge:
      provider: symphony-validator
      rubric: [structure, grounding, secrets, path_safety, available_agents]
      pass_threshold: 0.8
    refiner:
      provider: symphony-validator
      max_attempts: 3
      strategy: fix_judge_findings
    ---
    # Workflow

    ## Identity
    - Project: TODO: unresolved
    - Workspace: TODO: unresolved
    - Workflow version: 1
    - Source context: unresolved; user confirmation required.

    ## Objective
    #{objective}

    ## Inputs
    - TODO: identify real task/source inputs.

    ## Agents
    - TODO: reference configured agents only, or mark required agents as missing.

    ## Phases
    - Intake: confirm real task context.
    - Execute: perform scoped implementation.
    - Review: judge output against validation gates.
    - Refine: fix judge findings without inventing facts.

    ## Validation Gates
    - Required sections are present.
    - No embedded secrets.
    - Referenced paths and agents are real or explicitly unresolved.

    ## Artifacts
    - TODO: list real expected artifacts.

    ## Location and Activation
    - Target file: WORKFLOW.md
    - Activation requires explicit user confirmation.

    ## Guardrails
    - Do not invent tasks, agents, commands, integrations, or paths.
    - Destructive operations require human approval.

    ## Escalation
    - Block and ask the operator when required context is missing.

    ## Change Log
    - Initial scaffold generated by Symphony.
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp template("linear_codex_judge_refiner", o) do
    name = value(o, "name", "linear-codex-orchestra")

    objective =
      value(
        o,
        "objective",
        "Process real Linear issues with Codex, then judge and refine outputs before completion."
      )

    max_agents = value(o, "max_concurrent_agents", "2")
    poll = value(o, "poll_interval_ms", "30000")
    profiles = companion_agent_profiles("linear_codex_judge_refiner", o)
    generator_profile = profile_ref(o, profiles, "generator", "workflow-generator")
    builder_profile = profile_ref(o, profiles, "builder", "workflow-builder")
    judge_profile = profile_ref(o, profiles, "judge", "workflow-judge")
    refiner_profile = profile_ref(o, profiles, "refiner", "workflow-refiner")

    """
    ---
    schema_version: 1
    name: #{yaml(name)}
    description: Linear issue intake with Codex execution plus judge/refiner review gates.
    tracker:
      kind: linear
      endpoint: https://api.linear.app/graphql
      api_key: $LINEAR_API_KEY
      project_slug: $LINEAR_PROJECT_SLUG
      active_states: [Todo, In Progress]
      terminal_states: [Closed, Cancelled, Canceled, Duplicate, Done]
    polling:
      interval_ms: #{poll}
    workspace:
      root: ./symphony_workspaces
    hooks:
      timeout_ms: 30000
    agent:
      max_concurrent_agents: #{max_agents}
      max_turns: 20
      max_retry_backoff_ms: 300000
      profiles_path: ./agent_profiles.json
    codex:
      command: codex app-server
      turn_timeout_ms: 3600000
      read_timeout_ms: 5000
      stall_timeout_ms: 300000
    server:
      port: 4004
    generator:
      provider: codex
      profile: #{yaml(generator_profile)}
      instructions: Draft implementation plans using only real issue context and repository facts.
    builder:
      provider: codex
      profile: #{yaml(builder_profile)}
      instructions: Run Codex against the issue workspace with scoped repository changes.
    judge:
      provider: codex
      profile: #{yaml(judge_profile)}
      rubric: [tests_pass, implementation_matches_issue, no_unrequested_file_changes, no_embedded_secrets]
      pass_threshold: 0.8
    refiner:
      provider: codex
      profile: #{yaml(refiner_profile)}
      max_attempts: 3
      strategy: fix_judge_findings
    stage_agents:
    #{stage_agents_yaml("linear_codex_judge_refiner", o)}
    ---
    # Workflow

    ## Identity
    - Project: $LINEAR_PROJECT_SLUG
    - Workspace: ./symphony_workspaces
    - Workflow version: 1
    - Source context: Linear issue payload and repository/workspace files available to the runner.

    ## Objective
    #{objective}

    ## Inputs
    - Real Linear issue identifier: {{ issue.identifier }}
    - Real Linear issue title: {{ issue.title }}
    - Real Linear issue state: {{ issue.state }}
    - Attempt number: {{ attempt }}

    ## Agents
    - Generator: prepares scoped execution using real issue context.
    - Builder: runs Codex against the issue workspace.
    - Judge: evaluates output against the rubric.
    - Refiner: fixes judge findings without inventing new facts.

    ## Phases
    - Overture / Intake: poll Linear and claim eligible active issues.
    - Movement I / Build: run Codex in the issue workspace.
    - Movement II / Judge: verify outputs, file changes, and safety constraints.
    - Movement III / Refine: address judge findings with bounded retries.
    - Finale / Complete: mark work ready only after validation gates pass.

    ## Validation Gates
    - Issue context must be real and present.
    - Secrets must remain environment references, never literal values.
    - Generated or changed files must stay inside the workspace/repository policy.
    - Judge findings must be resolved or explicitly escalated.

    ## Artifacts
    - Workspace changes in ./symphony_workspaces/{{ issue.identifier }}
    - Agent event logs and final operator summary.

    ## Location and Activation
    - Target file: WORKFLOW.md
    - Runtime reload is not supported yet; backend restart is required after activation.

    ## Guardrails
    - Do not create fake tasks, agents, commands, integrations, or issue IDs.
    - Do not embed API keys, tokens, passwords, or secret values.
    - Destructive actions and external writes require explicit human approval.

    ## Escalation
    - Escalate blocked credentials, missing repositories, unavailable agents, and unsafe changes.

    ## Change Log
    - Initial Linear/Codex judge-refiner workflow generated by Symphony.
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp template("repository_orchestra", o) do
    name = value(o, "name", "repository-orchestra")

    objective =
      value(
        o,
        "objective",
        "Coordinate repository work through explicit implementation, review, and validation phases."
      )

    project_path = value(o, "project_path", "TODO: unresolved project path")
    profiles = companion_agent_profiles("repository_orchestra", o)
    generator_profile = profile_ref(o, profiles, "generator", "repository-workflow-generator")
    builder_profile = profile_ref(o, profiles, "builder", "repository-workflow-builder")
    judge_profile = profile_ref(o, profiles, "judge", "repository-workflow-judge")
    refiner_profile = profile_ref(o, profiles, "refiner", "repository-workflow-refiner")
    validator_profile = profile_ref(o, profiles, "validator", "repository-workflow-validator")

    """
    ---
    schema_version: 1
    name: #{yaml(name)}
    description: Repository-grounded multi-agent workflow scaffold.
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: $LINEAR_PROJECT_SLUG
    workspace:
      root: ./symphony_workspaces
    agent:
      max_concurrent_agents: 2
      max_turns: 20
      profiles_path: ./agent_profiles.json
    codex:
      command: codex app-server
    server:
      port: 4004
    generator:
      provider: codex
      profile: #{yaml(generator_profile)}
    builder:
      provider: codex
      profile: #{yaml(builder_profile)}
    judge:
      provider: codex
      profile: #{yaml(judge_profile)}
      rubric: [source_attribution, commands_verified, agents_available, no_embedded_secrets]
    refiner:
      provider: codex
      profile: #{yaml(refiner_profile)}
      max_attempts: 3
    validator:
      provider: codex
      profile: #{yaml(validator_profile)}
    stage_agents:
    #{stage_agents_yaml("repository_orchestra", o)}
    ---
    # Workflow

    ## Identity
    - Project: #{project_path}
    - Workspace: ./symphony_workspaces
    - Workflow version: 1
    - Source context: repository files selected by the operator; unresolved until scanned.

    ## Objective
    #{objective}

    ## Inputs
    - Repository path: #{project_path}
    - Task source: real connected issue provider or manually supplied requirement.

    ## Agents
    - Use configured Symphony agent profiles only.
    - Missing desired agents must be marked as unavailable rather than assumed runnable.

    ## Phases
    - Score Reading: inspect real repository context.
    - Composition: implement scoped changes.
    - Rehearsal: run available project validation commands.
    - Critique: judge changes and identify refinements.
    - Performance: prepare final summary and artifacts.

    ## Validation Gates
    - Commands must come from repository files or be marked unresolved.
    - Paths must remain inside allowed project/workspace roots.
    - Judge approval is required before activation/completion.

    ## Artifacts
    - Changed files, validation output, and operator summary.

    ## Location and Activation
    - Target file: WORKFLOW.md
    - Activation requires explicit confirmation and backend restart until reload is wired.

    ## Guardrails
    - No fake project facts, commands, agents, or task IDs.
    - No embedded secrets.

    ## Escalation
    - Ask the operator for missing project context or unavailable agents.

    ## Change Log
    - Initial repository orchestra workflow generated by Symphony.
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp companion_agent_profiles_from_content(content) do
    with {:ok, wf} <- Loader.parse(content),
         stage_agents when is_list(stage_agents) <- wf.config["stage_agents"] do
      stage_agents
      |> Enum.map(&profile_from_stage_agent/1)
      |> Enum.reject(&is_nil/1)
    else
      _ -> []
    end
  end

  defp profile_from_stage_agent(raw) when is_map(raw) do
    raw = stringify(raw)
    music = raw["music"] |> map_or_empty() |> stringify()
    stage = (raw["stage"] || raw["stage_position"]) |> map_or_empty() |> stringify()
    id = raw["id"] || raw["profile"] || raw["profile_key"]

    if present?(id) do
      section = raw["section"] || music["section"] || "Strings"
      instrument = raw["instrument_name"] || raw["instrument"] || music["instrument"]

      %{
        "id" => id,
        "name" => raw["name"] || humanize(id),
        "role" => raw["role"] || "Agent",
        "profile_key" => raw["profile_key"] || id,
        "section" => section,
        "instrument_name" => instrument,
        "description" => raw["description"] || "",
        "instructions" => raw["instructions"] || "",
        "capabilities" => list_strings(raw["capabilities"]),
        "music" =>
          Map.merge(music, %{
            "section" => section,
            "instrument" => instrument || "",
            "motif" => raw["motif"] || music["motif"] || ""
          }),
        "stage_position" => stage
      }
    end
  end

  defp profile_from_stage_agent(_), do: nil

  defp base_companion_profiles(template_id), do: Map.get(@companion_profiles, template_id, [])

  defp apply_profile_overrides(profiles, overrides) do
    overrides = stringify(overrides || %{})

    profiles
    |> Enum.map(fn profile ->
      role = profile["role"] |> to_string() |> String.downcase()

      case selected_profile_id(overrides, role) do
        nil -> profile
        id -> selected_stage_profile(id, profile)
      end
    end)
    |> Enum.uniq_by(& &1["id"])
  end

  defp selected_stage_profile(id, fallback) do
    case registry_profile(id) do
      {:ok, profile} ->
        profile = stringify(profile)

        fallback
        |> Map.merge(profile)
        |> Map.put("id", id)
        |> Map.put("profile_key", profile["profile_key"] || id)

      _ ->
        fallback
        |> Map.put("id", id)
        |> Map.put("profile_key", id)
        |> Map.put("name", humanize(id))
    end
  end

  defp registry_profile(id) do
    if Process.whereis(Symphony.AgentProfileRegistry) do
      Symphony.AgentProfileRegistry.get(id)
    else
      {:error, :registry_unavailable}
    end
  catch
    :exit, _ -> {:error, :registry_unavailable}
  end

  defp profile_ref(overrides, profiles, role, fallback) do
    selected_profile_id(overrides, role) || role_profile_id(profiles, role, fallback)
  end

  defp role_profile_id(profiles, role, fallback) do
    profiles
    |> Enum.find(fn profile ->
      profile["role"] |> to_string() |> String.downcase() == role
    end)
    |> case do
      nil -> fallback
      profile -> profile["id"] || fallback
    end
  end

  defp selected_profile_id(overrides, role) do
    overrides = stringify(overrides || %{})
    profiles = overrides["profiles"] |> map_or_empty() |> stringify()

    [
      overrides["#{role}_profile"],
      overrides["#{role}_profile_id"],
      profiles[role],
      profiles["#{role}_profile"],
      profiles["#{role}_profile_id"]
    ]
    |> Enum.find(&present?/1)
  end

  defp stage_agents_yaml(template_id, overrides) do
    template_id
    |> companion_agent_profiles(overrides)
    |> Enum.map(&stage_agent_yaml/1)
    |> Enum.join("\n")
  end

  defp stage_agent_yaml(profile) do
    music = profile["music"] || %{}
    stage = profile["stage_position"] || %{}

    """
      - profile: #{yaml(profile["id"])}
        name: #{yaml(profile["name"])}
        role: #{yaml(profile["role"])}
        profile_key: #{yaml(profile["profile_key"])}
        section: #{yaml(profile["section"])}
        instrument: #{yaml(profile["instrument_name"])}
        description: #{yaml(profile["description"])}
        instructions: #{yaml(profile["instructions"])}
        capabilities: #{yaml_list(profile["capabilities"] || [])}
        music:
          section: #{yaml(profile["section"])}
          instrument: #{yaml(profile["instrument_name"])}
          motif: #{yaml(music["motif"] || "")}
          dynamic: #{yaml(music["dynamic"] || "")}
          register: #{yaml(music["register"] || "")}
        stage:
          section: #{yaml(stage["section"] || "")}
          seat: #{yaml(stage["seat"] || "")}
    """
    |> String.trim_trailing()
  end

  defp content_from(attrs, opts) do
    cond do
      is_binary(attrs["content"]) ->
        {:ok, attrs["content"]}

      is_binary(attrs["template_id"]) or is_binary(attrs["template"]) ->
        render_template(
          attrs["template_id"] || attrs["template"],
          attrs["overrides"] || attrs["context"] || %{}
        )

      is_binary(attrs["path"]) ->
        with {:ok, path} <- resolve_workflow_path(attrs["path"], opts), do: File.read(path)

      true ->
        {:error, {:validation, "content, template_id, or path is required"}}
    end
  end

  defp validation_for(content, opts) do
    parse =
      case Loader.parse(content) do
        {:ok, wf} -> {:ok, wf}
        {:error, reason} -> {:error, reason}
      end

    errors = []
    warnings = []

    {errors, warnings, wf} =
      case parse do
        {:ok, wf} ->
          errors = errors ++ required_body_errors(wf.prompt_template) ++ secret_errors(content)

          warnings =
            warnings ++
              heading_warnings(wf.prompt_template) ++
              placeholder_warnings(wf.prompt_template) ++ metadata_warnings(wf.config)

          {errors, warnings, wf}

        {:error, reason} ->
          {["parse error: #{inspect(reason)}" | errors], warnings, nil}
      end

    dispatch =
      if wf do
        {:ok, cfg} =
          Config.from_workflow(
            Path.join(root(Keyword.get(opts, :config) || current_config()), "WORKFLOW.md"),
            wf
          )

        Config.validate_dispatch(cfg)
      else
        {:error, [:parse_failed]}
      end

    dispatch_errors = dispatch_errors(dispatch)

    %{
      ok: true,
      valid: errors == [] and dispatch_errors == [],
      writable: errors == [],
      errors: errors,
      warnings: warnings,
      parse: %{ok: match?({:ok, _}, parse)},
      dispatch: %{ok: dispatch == :ok, errors: dispatch_errors},
      metadata: if(wf, do: metadata(wf), else: %{}),
      content_sha256: sha256(content)
    }
  end

  defp required_body_errors(body) do
    if String.trim(body || "") == "", do: ["prompt body is required"], else: []
  end

  defp secret_errors(content) do
    secret_patterns = [
      ~r/(ghp_|sk-[A-Za-z0-9]|xox[baprs]-|api[_-]?key\s*[:=]\s*[A-Za-z0-9_\-]{16,})/i
    ]

    if Enum.any?(secret_patterns, &Regex.match?(&1, content)),
      do: ["embedded secret-like value detected"],
      else: []
  end

  defp heading_warnings(body) do
    Enum.flat_map(@required_headings, fn heading ->
      if String.contains?(body || "", "## #{heading}"),
        do: [],
        else: ["missing recommended section: #{heading}"]
    end)
  end

  defp placeholder_warnings(body) do
    Regex.scan(~r/{{\s*([^}]+?)\s*}}/, body || "")
    |> Enum.map(fn [_, key] -> String.trim(key) end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in @known_placeholders))
    |> Enum.map(&"unknown placeholder: #{&1}")
  end

  defp metadata_warnings(config) do
    []
    |> maybe_warn(Map.has_key?(config, "generator"), "missing generator metadata")
    |> maybe_warn(Map.has_key?(config, "judge"), "missing judge metadata")
    |> maybe_warn(Map.has_key?(config, "refiner"), "missing refiner metadata")
  end

  defp maybe_warn(warnings, true, _), do: warnings
  defp maybe_warn(warnings, false, msg), do: [msg | warnings]

  defp dispatch_errors(:ok), do: []
  defp dispatch_errors({:error, errors}) when is_list(errors), do: Enum.map(errors, &inspect/1)
  defp dispatch_errors({:error, reason}), do: [inspect(reason)]

  defp review_content(_content, validation) do
    score = max(0, 100 - length(validation.errors) * 30 - length(validation.warnings) * 5)

    %{
      verdict:
        cond do
          validation.errors != [] -> "blocked"
          validation.warnings != [] -> "needs_refinement"
          true -> "pass"
        end,
      score: score,
      judge: %{
        provider: "Symphony.Workflow.Files",
        findings: validation.errors,
        warnings: validation.warnings,
        safe_to_save: validation.errors == [],
        safe_to_activate: validation.valid
      },
      refiner: %{
        provider: "Symphony.Workflow.Files",
        summary: refiner_summary(validation),
        proposed_content: nil
      }
    }
  end

  defp refiner_summary(%{errors: [], warnings: []}), do: "No refinement required."

  defp refiner_summary(%{errors: errors}) when errors != [],
    do: "Resolve blocking validation errors before saving."

  defp refiner_summary(_),
    do: "Review warnings and either refine the draft or accept them explicitly."

  defp summary(path, root, active) do
    stat = File.stat!(path)

    meta =
      case Loader.load(path) do
        {:ok, wf} -> metadata(wf) |> Map.put(:valid, true)
        {:error, reason} -> %{valid: false, error: inspect(reason)}
      end

    Map.merge(meta, %{
      path: Path.relative_to(path, root),
      absolute_path: path,
      active: Path.expand(path) == active,
      size_bytes: stat.size,
      modified_at: stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
    })
  end

  defp metadata(wf) do
    %{
      name: wf.config["name"] || "WORKFLOW.md",
      schema_version: wf.config["schema_version"],
      has_generator: is_map(wf.config["generator"]),
      has_judge: is_map(wf.config["judge"]),
      has_refiner: is_map(wf.config["refiner"]),
      tracker: %{
        kind: get_in(wf.config, ["tracker", "kind"]),
        project_slug: get_in(wf.config, ["tracker", "project_slug"]),
        has_api_key: present?(get_in(wf.config, ["tracker", "api_key"]))
      }
    }
  end

  defp redact_config(config) when is_map(config) do
    Map.new(config, fn
      {k, v} when k in ["api_key", "token", "password", "secret"] -> {k, redacted(v)}
      {k, v} when is_map(v) -> {k, redact_config(v)}
      {k, v} when is_list(v) -> {k, Enum.map(v, &if(is_map(&1), do: redact_config(&1), else: &1))}
      pair -> pair
    end)
  end

  defp redacted(nil), do: nil
  defp redacted("$" <> env), do: "$" <> env
  defp redacted(v) when is_binary(v), do: if(String.trim(v) == "", do: v, else: "[redacted]")
  defp redacted(_), do: "[redacted]"

  defp resolve_workflow_path(nil, _opts), do: {:error, {:validation, "path is required"}}

  defp resolve_workflow_path(path, opts) when is_binary(path) do
    config = Keyword.get(opts, :config) || current_config()
    root = root(config)

    cond do
      Path.type(path) == :absolute ->
        {:error, {:unsafe_path, "absolute paths are not accepted by the workflow API"}}

      String.contains?(path, <<0>>) ->
        {:error, {:unsafe_path, "null byte in path"}}

      Path.basename(path) != "WORKFLOW.md" ->
        {:error, {:unsafe_path, "workflow files must be named WORKFLOW.md"}}

      true ->
        segs = Path.split(path)

        with {:ok, target} <- SafePath.safe_join(root, segs),
             :ok <- reject_symlink_parents(root, Path.dirname(target)),
             :ok <- SafePath.reject_symlink(target) do
          {:ok, target}
        else
          {:error, reason} -> {:error, {:unsafe_path, inspect(reason)}}
        end
    end
  end

  defp reject_symlink_parents(root, parent) do
    rel = Path.relative_to(parent, root)

    if rel == "." do
      :ok
    else
      rel
      |> Path.split()
      |> Enum.reduce_while(root, fn seg, acc ->
        path = Path.join(acc, seg)

        case SafePath.reject_symlink(path) do
          :ok -> {:cont, path}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        p when is_binary(p) -> :ok
        error -> error
      end
    end
  end

  defp conflict(path, true), do: SafePath.reject_symlink(path)
  defp conflict(path, false), do: if(File.exists?(path), do: {:error, :conflict}, else: :ok)
  defp exists(path), do: if(File.exists?(path), do: :ok, else: {:error, :not_found})
  defp valid_for_write(%{writable: true}), do: :ok
  defp valid_for_write(%{errors: errors}), do: {:error, {:validation, errors}}

  defp valid_for_write(validation),
    do: {:error, {:validation, Map.get(validation, :errors, ["workflow is not writable"])}}

  defp atomic_write(path, content) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      tmp = path <> ".tmp-" <> short_hash(content)
      File.write!(tmp, content)
      File.rename(tmp, path)
    end
  end

  defp copy_move(attrs, opts) do
    with {:ok, source} <- resolve_workflow_path(attrs["source_path"] || attrs["from"], opts),
         {:ok, dest} <- resolve_workflow_path(attrs["destination_path"] || attrs["to"], opts),
         {:ok, body} <- File.read(source),
         :ok <- atomic_write(dest, body),
         :ok <- File.rm(source) do
      {:ok,
       %{
         ok: true,
         moved: true,
         source_path: rel(source, opts),
         destination_path: rel(dest, opts),
         restart_required: false,
         reload_required: true,
         reload_supported: true
       }}
    end
  end

  defp active_path?(path, opts) do
    config = Keyword.get(opts, :config) || current_config()
    Path.expand(path) == Path.expand(config.workflow_path || "WORKFLOW.md")
  end

  defp rel(path, opts) do
    config = Keyword.get(opts, :config) || current_config()
    Path.relative_to(path, root(config))
  end

  defp root(config),
    do:
      Path.expand(
        config.workflow_dir || Path.dirname(config.workflow_path || Path.expand("WORKFLOW.md"))
      )

  defp current_config do
    case Config.load() do
      {:ok, c} -> c
      _ -> %Config{workflow_dir: Path.expand(".")}
    end
  end

  defp unsafe_existing?(path), do: SafePath.reject_symlink(path) != :ok
  defp stringify(m) when is_map(m), do: Map.new(m, fn {k, v} -> {to_string(k), stringify(v)} end)
  defp stringify(l) when is_list(l), do: Enum.map(l, &stringify/1)
  defp stringify(v), do: v
  defp map_or_empty(v) when is_map(v), do: v
  defp map_or_empty(_), do: %{}
  defp value(map, key, default), do: map[key] || default
  defp yaml(v), do: inspect(to_string(v))
  defp yaml_list(values), do: "[" <> (values |> Enum.map(&yaml/1) |> Enum.join(", ")) <> "]"

  defp humanize(v),
    do:
      v
      |> to_string()
      |> String.replace(~r/[-_]+/, " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp list_strings(v) when is_list(v),
    do: v |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp list_strings(v) when is_binary(v),
    do: v |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp list_strings(_), do: []
  defp bool(v, _default) when is_boolean(v), do: v
  defp bool(nil, default), do: default

  defp bool(v, default) when is_binary(v),
    do:
      String.downcase(v) in ["true", "1", "yes"] ||
        (default and String.downcase(v) not in ["false", "0", "no"])

  defp bool(_, default), do: default
  defp present?(v), do: is_binary(v) and String.trim(v) != ""
  defp sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  defp short_hash(content), do: sha256(content) |> binary_part(0, 12)
end

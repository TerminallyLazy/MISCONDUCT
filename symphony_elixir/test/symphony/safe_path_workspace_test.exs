defmodule Symphony.SafePathWorkspaceTest do
  use ExUnit.Case, async: false
  alias Symphony.Filesystem.SafePath

  test "sanitizes identifiers and rejects traversal" do
    assert SafePath.sanitize_segment("TEAM/123 😈") == "TEAM_123_____"
    assert {:error, :slash_segment} = SafePath.safe_join("/tmp/root", ["../evil"])
    assert {:error, :absolute_segment} = SafePath.safe_join("/tmp/root", ["/evil"])
    assert SafePath.inside_root?("/tmp/root", "/tmp/root/card")
    refute SafePath.inside_root?("/tmp/root", "/tmp/root2/card")
  end

  test "workspace manager creates deterministic contained workspace and hooks" do
    root = Path.join(System.tmp_dir!(), "symws_#{System.unique_integer([:positive])}")
    wf = %Symphony.Workflow{config: %{}, prompt_template: "x"}

    config = %Symphony.Config{
      workflow: wf,
      workflow_path: "x",
      workflow_dir: File.cwd!(),
      workspace_root: root,
      tracker_kind: "linear",
      tracker_api_key: "k",
      tracker_project_slug: "p",
      hooks: %{"after_create" => "echo created > hook.txt"}
    }

    start_supervised!({Symphony.Workspace.Manager, [root: root, name: :workspace_test_mgr]})

    {:ok, ws} =
      Symphony.Workspace.Manager.create_for_issue("LIN/123", config, :workspace_test_mgr)

    assert ws.workspace_key == "LIN_123"
    assert String.starts_with?(ws.path, Path.expand(root) <> "/")
    assert File.read!(Path.join(ws.path, "hook.txt")) =~ "created"

    {:ok, ws2} =
      Symphony.Workspace.Manager.create_for_issue("LIN/123", config, :workspace_test_mgr)

    refute ws2.created_now
  end
end

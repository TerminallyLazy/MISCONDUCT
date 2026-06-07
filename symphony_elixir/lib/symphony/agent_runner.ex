defmodule Symphony.AgentRunner do
  @callback run(Symphony.Run.t(), Symphony.Workspace.t(), Symphony.Config.t(), pid()) ::
              :ok | {:error, term()}
end

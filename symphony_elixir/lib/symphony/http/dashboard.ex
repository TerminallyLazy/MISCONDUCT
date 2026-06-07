defmodule Symphony.Http.Dashboard do
  @moduledoc false

  def html do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Symphony Dashboard</title>
        <style>
          :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
          body { margin: 0; min-height: 100vh; background: radial-gradient(circle at top left, #23305f, #080b15 48%, #05060a); color: #eef2ff; }
          main { width: min(1120px, calc(100vw - 40px)); margin: 0 auto; padding: 56px 0; }
          h1 { margin: 0 0 8px; font-size: clamp(2rem, 5vw, 4rem); letter-spacing: -0.06em; }
          p { color: #aeb9d8; line-height: 1.7; }
          .panel { margin-top: 28px; padding: 24px; border: 1px solid rgba(180, 200, 255, 0.18); border-radius: 24px; background: rgba(12, 18, 35, 0.68); box-shadow: 0 24px 80px rgba(0,0,0,.35); }
          .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; }
          a, button { color: #dbe7ff; }
          code { color: #9fe4ff; }
        </style>
      </head>
      <body>
        <main>
          <p>Agent-centric Elixir orchestrator</p>
          <h1>Symphony Dashboard</h1>
          <p>Use the JSON operator API for the desktop console, workflow diagnostics, Kanban state, and issue-level debugging.</p>
          <section class="panel grid">
            <div><strong>Health</strong><p><code>GET /healthz</code></p></div>
            <div><strong>State</strong><p><code>GET /api/v1/state</code></p></div>
            <div><strong>Kanban</strong><p><code>GET /api/kanban</code></p></div>
            <div><strong>Workflow</strong><p><code>GET /api/workflow</code></p></div>
          </section>
        </main>
      </body>
    </html>
    """
  end
end

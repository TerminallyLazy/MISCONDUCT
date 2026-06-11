# MISCONDUCT

MISCONDUCT is a desktop orchestration app for coordinating manual movements, optional Linear issues, Codex-backed agents, workflow files, agent profiles, and live task state.

## Desktop downloads

Download packaged builds from GitHub Releases:

https://github.com/TerminallyLazy/MISCONDUCT/releases/latest

Current app metadata in this checkout is `0.1.19`. The public latest release page
is updated by pushing the matching release tag and letting the desktop workflow
publish the new artifacts.

The GitHub Actions workflow `.github/workflows/release-desktop.yml` is configured to build macOS arm64, Windows x86_64, and Linux x86_64 packages from release tags.

## Development

Frontend/Tauri desktop app is at the repository root.

```bash
npm install
npm run build
npm run tauri:build
```

`npm run tauri:build` builds and stages the Elixir Mix release into `src-tauri/resources/symphony_backend` before Tauri packages the MISCONDUCT desktop app.

Backend source lives in `symphony_elixir/`.

```bash
cd symphony_elixir
mix test
```

## Codex auth model

MISCONDUCT uses the Codex CLI as the OAuth/session owner for ChatGPT/Codex Pro. The app exposes sanitized status and login/check/logout controls; it does not ask users to paste OAuth tokens.

## Release automation note

The cross-platform GitHub Actions workflow is now included at `.github/workflows/release-desktop.yml`. It builds downloadable macOS arm64, Windows x86_64, and Linux x86_64 desktop artifacts from release tags.

Current downloadable assets are published on the GitHub Release page.

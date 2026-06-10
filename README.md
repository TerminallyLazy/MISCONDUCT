# Misconducting / Symphony Console

A pixel-art orchestral conductor console for coordinating manual Symphony movements, optional Linear issues, Codex-backed agents, workflow files, agent profiles, and live task state.

## Desktop downloads

Download packaged builds from GitHub Releases:

https://github.com/TerminallyLazy/misconducting/releases/latest

Current app metadata in this checkout is `0.1.14`. The public latest release page may
still show older assets until tag `v0.1.14` is pushed and the desktop release workflow
publishes new artifacts.

The GitHub Actions workflow `.github/workflows/release-desktop.yml` is configured to build macOS, Windows, Linux x86_64, and Linux ARM64 packages from release tags.

## Development

Frontend/Tauri desktop app is at the repository root.

```bash
npm install
npm run build
npm run tauri:build
```

`npm run tauri:build` builds and stages the Elixir Mix release into `src-tauri/resources/symphony_backend` before Tauri packages the desktop app.

Backend source lives in `symphony_elixir/`.

```bash
cd symphony_elixir
mix test
```

## Codex auth model

Symphony uses the Codex CLI as the OAuth/session owner for ChatGPT/Codex Pro. The app exposes sanitized status and login/check/logout controls; it does not ask users to paste OAuth tokens.

## Release automation note

The cross-platform GitHub Actions workflow is now included at `.github/workflows/release-desktop.yml`. It builds downloadable macOS, Windows, Linux x86_64, and Linux ARM64 desktop artifacts from release tags.

Current downloadable assets are published on the GitHub Release page.

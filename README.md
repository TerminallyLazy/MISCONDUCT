# Misconducting / Symphony Console

A pixel-art orchestral conductor console for coordinating real Linear issues, Codex-backed agents, workflow files, agent profiles, and live task state.

## Desktop downloads

Download packaged builds from GitHub Releases:

https://github.com/TerminallyLazy/misconducting/releases/latest

Current locally built release assets are Linux ARM64:

- `Symphony Console_0.1.4_aarch64.AppImage`
- `Symphony Console_0.1.4_arm64.deb`

The GitHub Actions workflow `.github/workflows/release-desktop.yml` is configured to build macOS, Windows, Linux x86_64, and Linux ARM64 packages from release tags.

## Development

Frontend/Tauri desktop app is at the repository root.

```bash
npm install
npm run build
npm run tauri:build
```

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

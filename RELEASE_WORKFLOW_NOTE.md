# Cross-platform release workflow note

The desktop release workflow is prepared locally at:

`/a0/usr/workdir/symphony_desktop/.github/workflows/release-desktop.yml`

It builds:

- macOS universal DMG
- Windows x86_64 NSIS installer
- Linux x86_64 AppImage/DEB
- Linux ARM64 AppImage/DEB

It could not be pushed with the current GitHub token because the token lacks the `workflow` scope.

To enable automated cross-platform builds, provide a PAT with `repo` + `workflow` scopes, then push that workflow file.

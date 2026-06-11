# Cross-platform release workflow

The desktop release workflow is active at `.github/workflows/release-desktop.yml`.

It builds:

- macOS arm64 DMG
- Windows x86_64 NSIS installer
- Linux x86_64 AppImage/DEB

Push a release tag such as `v0.1.19` or run the workflow manually from GitHub Actions to produce MISCONDUCT release artifacts.

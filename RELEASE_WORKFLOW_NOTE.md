# Cross-platform release workflow

The desktop release workflow is active at `.github/workflows/release-desktop.yml`.

It builds:

- macOS universal DMG
- Windows x86_64 NSIS installer
- Linux x86_64 AppImage/DEB
- Linux ARM64 AppImage/DEB

Push tag `v0.1.7` or run the workflow manually from GitHub Actions to produce release artifacts.

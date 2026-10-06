# Packaging

`../.github/workflows/release.yml` builds, on every `v*` tag or by hand:

- macOS: a signed, notarized, stapled disk image with the game's own
  backdrop and icon (`tools/mac_release.sh`, also runnable on a desk).
- Windows: a zip holding one executable with the game packed inside.
- Linux: an AppImage with this folder's desktop file, the icon and the
  AppStream data inside, which runs on any distribution without
  installing, plus a plain tarball.

No app stores. The AppImage and the GitHub release are the distribution.

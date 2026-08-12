# Changelog

All notable changes are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A download button at the top of the README, in a dark and a light variant so
  GitHub serves whichever matches the reader's theme. It points at the permanent
  link for the newest release, so it never has to be updated by hand.
  `make button` redraws both.

## [1.0.2] - 2026-08-10

### Fixed

- Stop drawing while the saver is not on screen. macOS does not always tear
  `legacyScreenSaver` down after an unlock, and a saver that keeps rendering
  behind the user's windows costs a core for pixels nobody sees. Frames are now
  skipped, and the sampler released, whenever the host window reports itself
  occluded.
- The published screenshots were rendered with live readings, which put the
  machine that made them into the process table. Every artwork tool now forces
  synthetic readings and masking, and the images have been redrawn.

### Added

- Homebrew cask in [perfectoweb/tap](https://github.com/PerfectoWeb/homebrew-tap),
  so installing is `brew install --cask perfectoweb/tap/gibson` and upgrades
  come with everything else.
- `SECURITY.md`, with the reporting channel and a plain account of what the
  saver reads and what it never does.
- `make social` draws the repository card from a real frame of the running
  saver.

## [1.0.1] - 2026-08-10

### Changed

- Release builds are signed with a Developer ID and notarised by Apple, and the
  ticket is stapled to the bundle. macOS no longer asks anyone to confirm a
  download, so the quarantine dance is gone from the instructions.
- The release workflow signs and notarises in CI, and falls back to an ad hoc
  build when the signing secrets are not available, so a fork still gets an
  artefact.

### Added

- Illustrated install walkthrough in `docs/INSTALL.md`, covering the dialogs
  macOS shows for a saver that is not notarised.

## [1.0.0] - 2026-08-10

First public release.

### The screen saver

- Universal `.saver` bundle for macOS 14 and newer, Apple silicon and Intel.
- Seventeen panels: header strip, wireframe globe, radar, process table, account
  dump, progress stack, vitals tiles, dial cluster, hex dump, helix, flow lanes,
  waveform, session log, file vault, digit rain, CPU load history and countdown.
- Live readings for the process table, CPU load per core, memory pressure, swap,
  volume capacity, network throughput, load average, uptime and thermal state.
  Everything else on screen is deliberately invented and documented as such.
- Layouts for landscape, portrait and the System Settings preview, each with two
  variants that alternate between sessions.
- Four colour schemes, all derived from a single hue per scheme.
- Cold boot sequence that shuffles its script on every launch, staggered panel
  fade in, CRT scanlines, vignette, and an occasional tear band.
- Support code: a QR for the author's donation page surfaces over the digit rain
  every few minutes, and the same URL is planted in the memory inspector as
  bytes that spell it out in the ASCII gutter. Generated with CoreImage.
- Easter eggs planted in the memory inspector and the session log.

### Development

- `make demo` runs the panels in a plain window, `make screenshot` renders a
  frame offscreen at any size, `make cover` regenerates the picker tile.
- `GIBSON_VARIANT` and `GIBSON_PALETTE` pin the layout and the colour scheme
  while working on a panel.
- CI builds the universal bundle and the helper tools, and verifies the bundle
  structure, architectures and signature. Tagging `v*` publishes a release with
  the zipped bundle attached.

[Unreleased]: https://github.com/PerfectoWeb/Gibson/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/PerfectoWeb/Gibson/releases/tag/v1.0.2
[1.0.1]: https://github.com/PerfectoWeb/Gibson/releases/tag/v1.0.1
[1.0.0]: https://github.com/PerfectoWeb/Gibson/releases/tag/v1.0.0

# GitHub Actions Binary Release

This repository now includes `.github/workflows/release-binaries.yml` for
automatically building and publishing MPD bundle archives to GitHub Releases.

## Trigger

- Push a tag like `v0.1.38`
- Or run `Release MPD Binaries` manually from GitHub Actions

Tag example:

```bash
git tag v0.1.38
git push origin v0.1.38
```

## What The Workflow Builds

Always built on GitHub-hosted runners:

- `linux-x86_64-glibc`
- `linux-x86_64-musl`

Optional, built only when self-hosted runners are enabled:

- `linux-arm64-glibc`
- `linux-arm64-musl`
- `linux-armv7-glibc`

Release file names:

- `dist/plugin-binaries/mpd-player-linux-x86_64-glibc.tgz`
- `dist/plugin-binaries/mpd-player-linux-x86_64-musl.tgz`
- `dist/plugin-binaries/mpd-player-linux-arm64-glibc.tgz`
- `dist/plugin-binaries/mpd-player-linux-arm64-musl.tgz`
- `dist/plugin-binaries/mpd-player-linux-armv7-glibc.tgz`

## Self-Hosted Runner Labels

Expected labels in the workflow:

- `linux-arm64-glibc` job:
  - `self-hosted`
  - `linux`
  - `arm64`
  - `glibc`
- `linux-arm64-musl` job:
  - `self-hosted`
  - `linux`
  - `arm64`
  - `musl`
- `linux-armv7-glibc` job:
  - `self-hosted`
  - `linux`
  - `arm`
  - `glibc`

## Repository Variables

Enable self-hosted jobs only after the matching runner is online.

Configure these repository variables in:

- `Settings -> Secrets and variables -> Actions -> Variables`

Variables:

- `ENABLE_ARM64_GLIBC_RUNNER=true`
- `ENABLE_ARM64_MUSL_RUNNER=true`
- `ENABLE_ARMV7_GLIBC_RUNNER=true`

If a variable is missing or not equal to `true`, that job is skipped.

## Release Behavior

- On tag push, the workflow uploads all generated `.tgz` assets to the matching
  GitHub Release.
- On manual dispatch, it only builds artifacts and stores them in the workflow run.

## Notes

- `linux-x86_64-musl` is built in an Alpine container on GitHub-hosted runners.
- The ARM jobs are still native-only and should run on matching self-hosted machines.
- The workflow publishes binary archives only. Plugin zip release automation can be
  added later as a separate workflow or a new job.

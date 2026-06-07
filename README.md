# Plugin Binaries Build Matrix

This project packages MPD/MPC directly inside the plugin at `bin/<platform>/`.

The recommended output is not a naked `/usr/bin/mpd` or `/usr/bin/mpc` copy.
Those system binaries usually depend on shared libraries that are not visible inside
the Songloft plugin runtime.

Instead, build a relocatable bundle with:

- `mpd` and `mpc` wrapper scripts
- `mpd.real` and `mpc.real` compiled binaries
- `lib/` with copied runtime dependencies

The plugin now distinguishes both CPU architecture and libc family.
Current planned bundle directories are:

- `bin/linux-x86_64-glibc/`
- `bin/linux-x86_64-musl/`
- `bin/linux-arm64-glibc/`
- `bin/linux-arm64-musl/`
- `bin/linux-armv7-glibc/`

## Build Targets

These scripts are native-only. They do not use qemu, Docker, or cross-compilation.
Run each script on a host or rootfs with the exact same architecture and libc family
as the target bundle.

### glibc Targets

Run these on Debian/Ubuntu or another glibc-based native environment:

```bash
chmod +x scripts/build-linux-x86_64-glibc.sh
chmod +x scripts/build-linux-arm64-glibc.sh
chmod +x scripts/build-linux-armv7-glibc.sh

./scripts/build-linux-x86_64-glibc.sh
./scripts/build-linux-arm64-glibc.sh
./scripts/build-linux-armv7-glibc.sh
```

Legacy aliases are still kept for convenience:

```bash
./scripts/build-amd64.sh
./scripts/build-arm64.sh
./scripts/build-armv7.sh
```

### musl Targets

Run these on Alpine or another musl-based native environment:

```bash
chmod +x scripts/build-linux-x86_64-musl.sh
chmod +x scripts/build-linux-arm64-musl.sh

./scripts/build-linux-x86_64-musl.sh
./scripts/build-linux-arm64-musl.sh
```

## Shared Defaults

All target scripts share the same defaults:

- `MPD 0.24.12`
- `mpc 0.35`
- target directory: `bin/<platform>/`
- working directory: `.build/plugin-binaries/<platform>/`
- upload archive: `dist/plugin-binaries/mpd-player-<platform>.tgz`

You can override versions or the output directory:

```bash
MPD_VERSION=0.24.12 MPC_VERSION=0.35 TARGET_DIR=/tmp/mpd-plugin-bin ./scripts/build-linux-x86_64-glibc.sh
```

## Dependency Installation

The common script installs build dependencies automatically:

- `glibc` targets use `apt-get`
- `musl` targets use `apk`

If you already installed build dependencies manually, skip package installation:

```bash
SKIP_SYS_PKG_INSTALL=1 ./scripts/build-linux-x86_64-glibc.sh
SKIP_SYS_PKG_INSTALL=1 ./scripts/build-linux-x86_64-musl.sh
```

You can also use the older package-manager-specific flags:

```bash
SKIP_APT=1 ./scripts/build-linux-arm64-glibc.sh
SKIP_APK=1 ./scripts/build-linux-arm64-musl.sh
```

## Output Layout

After a successful build:

```text
bin/<platform>/
  mpd
  mpc
  mpd.real
  mpc.real
  lib/
```

- `mpd` / `mpc`: shell wrappers that export `LD_LIBRARY_PATH`
- `mpd.real` / `mpc.real`: compiled binaries
- `lib/`: copied runtime libraries discovered via `ldd`

The script also creates a GitHub-ready archive:

```text
dist/plugin-binaries/mpd-player-<platform>.tgz
```

That archive contains `mpd`, `mpc`, `mpd.real`, `mpc.real`, and `lib/` at the
top level, which matches the plugin's one-click download expectation.

## Distribution

If you still want to package binaries directly into the plugin, rebuild the
plugin after `bin/<platform>/` is ready:

```bash
npm run build
```

For the current hosted-binary plan, upload `dist/plugin-binaries/mpd-player-<platform>.tgz`
to GitHub Releases and later fill those asset URLs into the plugin code.

## Notes

- This bundle strategy is chosen because the plugin runtime may not see the host
  system library paths.
- `mpc` is built with Meson fallback mode so `libmpdclient` is linked more cleanly.
- `mpd` is intentionally built with a reduced feature set to keep the bundle smaller
  while preserving local file playback and common Linux outputs.
- The common script validates both native architecture and native libc family before building.

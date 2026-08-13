# GrokA: native Grok Build for Android terminals

GrokA compiles the open-source Grok Build code directly for Android's
`aarch64-linux-android` target. It does not run the GNU/Linux release through a
proxy, patch release instructions, or replace the official `grok` command.

## Requirements

- ARM64 Android 9 or newer (API 28+)
- Termux, Tmix, or a compatible Android terminal environment
- An xAI account for Grok Build authentication

The build host needs Rust 1.94.0 and Android NDK r29. The build script discovers
the NDK through `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`, `ANDROID_HOME`, or common
SDK locations.

## Build and install

```sh
./termux/build-android.sh
./termux/install.sh \
  --binary target/aarch64-linux-android/release/xai-grok-pager
groka --version
groka doctor
groka login --device-auth
```

A packaged release can be extracted and installed directly:

```sh
tar -xzf groka-1.0.3-android-arm64.tar.gz
cd groka-1.0.3-android-arm64
./install.sh
groka
```

The installer creates `~/.local/bin/groka` and `~/.local/bin/grok-android`. It
keeps the upstream `grok` command untouched and backs up any launcher it
replaces. Release archives include the Apache-2.0 licence, third-party notices,
upstream source revision, exact Git commit, target API, Rust toolchain, and NDK
version used to produce the binary.

## Android behaviour

- Networking is native Android/Bionic networking and DNS. No loopback CONNECT
  proxy is required.
- Login and OAuth links use `termux-open-url`; file links use `termux-open`.
  `GROK_ANDROID_URL_OPENER` and `GROK_ANDROID_FILE_OPENER` can override those
  commands for a terminal fork.
- Text clipboard access uses `termux-clipboard-get` and
  `termux-clipboard-set`. Copying falls back to OSC 52 when the helper is not
  installed. The helper paths can be overridden with
  `GROK_ANDROID_CLIPBOARD_GET` and `GROK_ANDROID_CLIPBOARD_SET`.
- The launcher defaults `GROK_WORKER_THREADS=2` and `RAYON_NUM_THREADS=2` to
  reduce Android low-memory kills. Explicit environment values take priority.
- Theme detection uses explicit Grok appearance variables, OSC 11, and
  `COLORFGBG`; it does not pretend Android has a desktop theme service.
- Upstream self-update is disabled for this target because xAI's desktop Linux
  artifacts use a different ABI. Update GrokA through this repository.
- Microphone voice capture and image clipboard transfer are disabled in the
  native terminal build. Text input, TUI operation, shell tools, web access,
  MCP, ACP, and device authentication remain available.
- The desktop Landlock/Seatbelt sandbox backend is unavailable on Android.
  Android's per-app UID sandbox and Grok's own tool permission/trust controls
  still apply.

## Signal 9

Signal 9 is `SIGKILL`: the process was terminated immediately and could not
clean up. Android commonly sends it through `lmkd` when memory is tight, though
an external supervisor or `kill -9` can do the same. Exit status 137 is the
usual shell representation. The two-thread launcher default reduces the risk,
but no process can catch or ignore `SIGKILL`.

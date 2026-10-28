# Tuna Extensions

My extensions for [Tuna](https://tunaformac.com), the macOS launcher.

| Extension | What it does |
| --- | --- |
| [Keep Awake](KeepAwake) | Keep the Mac awake for a set time and see how long is left |
| [Cardinal](Cardinal) | Search every file on the Mac with [Cardinal](https://github.com/cardisoft/cardinal) as you type |

![Keep Awake](media/screenshots/keep-awake/status-on.png)

## Install

These extensions are not in the Tuna store. Tuna loads them from its development
extensions folder. They run inside Tuna's process, so only install builds you trust.

Requires Tuna 0.96 or later on an Apple silicon Mac.

### From a release

1. Download the extension's zip from [Releases](../../releases) and unzip it, for example
   `KeepAwakeTuna.framework`.
2. Remove the download quarantine and move it into Tuna's development extensions folder:
   ```sh
   cd ~/Downloads
   xattr -dr com.apple.quarantine KeepAwakeTuna.framework
   mkdir -p ~/Library/Application\ Support/Tuna/ExtensionsDev
   rm -rf ~/Library/Application\ Support/Tuna/ExtensionsDev/KeepAwakeTuna.framework
   mv KeepAwakeTuna.framework ~/Library/Application\ Support/Tuna/ExtensionsDev/
   ```
3. Quit and reopen Tuna.

### From source

Needs a Swift 6.4 or later toolchain (TunaKit 1.22 is built with Swift 6.4), for example
the macOS toolchain from [swift.org](https://www.swift.org/install/macos/).

```sh
./scripts/install.sh all --restart        # build every extension, install, restart Tuna
./scripts/install.sh KeepAwake --restart  # just one
```

Set `TOOLCHAIN` to pick a specific toolchain identifier (default: the newest one from
swift.org).

## Develop

```sh
xcrun --toolchain swift swift test   # tests for every extension
./scripts/package.sh KeepAwake       # dist/KeepAwakeTuna-<version>.zip for a release
```

Each extension is a folder with its `Sources`, `Tests`, `Info.plist` (bundle id, version,
principal class) and README. All of them share one Swift package, one TunaKit pin and the
scripts in `scripts/`. Release tags name the extension, e.g. `keepawake-v0.1.0`.

## License

[MIT](LICENSE)

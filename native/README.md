# Beacon (native)

A resident SwiftUI menu-bar app replacing the Raycast `menu-bar` command.

Raycast does not keep a menu-bar command running — it relaunches the whole
node + React + `@raycast/api` process on every `interval` tick, ~0.5 CPU-seconds
each. At a 30s refresh that is ~40 CPU-minutes/day regardless of what the
command does. A resident process pays that cost once.

`Sources/BeaconCore` is a straight port of the pure logic in `../src`
(formatting, preference parsing, both alert evaluators, the menu model, quote
fetching + fallback) with its tests; `Sources/Beacon` is the app shell.
Dropped as Raycast-only workarounds: the quote cache, the fresh-quote alert
scheduler, and the curl/scutil proxy fallback — `URLSession` reads the system
proxy itself.

## Build

```bash
make build      # → .build/Beacon.app
make run        # build + open
make install    # → /Applications/Beacon.app
```

Signs with the `Developer ID Application` identity from `Makefile.local`
(gitignored; see the Makefile header), ad-hoc otherwise. Ad-hoc works, but the
signature changes on every rebuild, so macOS re-asks for keychain access (the
relay token) each time.

## Release

```bash
make release VERSION=1.0.0
```

Checks the version against `Resources/Info.plist`, builds a notarized DMG,
publishes a GitHub Release, and bumps the `beacon` cask in
`giraphant/homebrew-tap` — after which `brew upgrade --cask beacon` works.
Same flow as veduta's.

## Test

```bash
make test       # DEVELOPER_DIR-wrapped swift test
```

`XCTest` only ships inside Xcode.app; without the `DEVELOPER_DIR` override a
CommandLineTools-selected toolchain fails with `no such module 'XCTest'`.
`swift build` needs no such override.

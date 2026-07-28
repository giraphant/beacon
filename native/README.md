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
./build-app.sh              # → build/Beacon.app, ad-hoc signed
open build/Beacon.app
```

Ad-hoc signing is enough for notifications and login-item registration, but the
signature changes on every rebuild, so macOS re-asks for keychain access (the
relay token) each time.

## Test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`XCTest` only ships inside Xcode.app; without `DEVELOPER_DIR` a
CommandLineTools-selected toolchain fails with `no such module 'XCTest'`.
`swift build` needs no such override.

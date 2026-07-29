---
name: verify
description: Verify Beacon packaging by running the built menu-bar app and observing live quote diagnostics.
---

1. Build `native/.build/Beacon.app` with the configured Developer ID identity.
2. Quit any running Beacon, then launch the build with `open -n native/.build/Beacon.app`.
3. Confirm `ps` shows the executable under `native/.build/Beacon.app/Contents/MacOS/Beacon` and it remains running for at least one refresh interval.
4. Read the latest `~/Library/Logs/Beacon/quote-diagnostics.jsonl` events. A successful run has a new `session_start`, followed by `fetch_success` and `display_decision` for the same session.
5. If Automation and Screen Recording permissions are available, also open the status item and capture the menu. Their absence does not prevent the diagnostic-based runtime check.

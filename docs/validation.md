# Validation record

Checked on November 9, 2026. The project is a local first version, not a notarized distribution release.

## Environment

| Item | Observed value |
| --- | --- |
| Operating system | macOS 26.7.1 |
| Architecture | Apple Silicon / arm64 |
| Swift | Apple Swift 6.3.3 |
| Developer tools | Standalone Apple Command Line Tools; full Xcode not installed |
| Minimum deployment target | macOS 14 |
| Runtime packages | None |

## Completed checks

- **Optimized build:** `./scripts/build.sh` produces a native arm64 application bundle.
- **Signing and metadata:** local ad-hoc signature verified with `codesign --verify --strict`; Info.plist passes `plutil -lint` and sets `LSUIElement = true`.
- **Tests:** 38 tests in four Swift Testing suites pass. The test script configures the framework and runtime search paths required by this standalone Command Line Tools installation. No XCTest dependency is needed.
- **Contract tests:** legacy and structured Claude weekly meters; Codex weekly quotas in either window position; missing, null, ambiguous and malformed data; percentage units and date formats.
- **Credential tests:** expiry, API-key / ID-token rejection, redacted debug output, header injection, private read-only files, unsafe permissions, symlink refusal and storage-mode parsing. All fixtures are synthetic.
- **Service and state tests:** fixed HTTPS GET requests, provider-specific headers, redirect delegate refusal, no auth retry or token renewal, HTTP and network errors, Retry-After, independent providers, overlapping refreshes, manual throttling, wake checks and stale values.
- **Live Codex request:** the official usage endpoint returned HTTP 200. The weekly quota was in `primary_window`, with `limit_window_seconds = 604800` and null `secondary_window`. The compiled application also successfully reported the live Codex quota using its production transport and parser.
- **Claude expiry handling:** the existing Keychain item was readable, but its usage request returned HTTP 401. The compiled application reports **Session expired** without attempting renewal or modifying the credential.
- **Interface rendering:** the real SwiftUI popover was rendered at 2× scale with sample data and visually reviewed. Documentation images include the normal quota view and an expired-session view. The preview substitutes only the AppKit menu control's ellipsis label because ImageRenderer cannot render that control.
- **Launch smoke check:** a sample-data menu bar application process launched successfully and remained running. This is a process check, not a complete interaction test.
- **Repository:** source, original image assets and documentation are stored in the private `mgalli97/weeklet` GitHub repository. No credentials, real account response fixtures or generated build caches are committed.

## Remaining manual verification

| Check | Why it remains |
| --- | --- |
| Successful authenticated Claude quota response | The available Claude access token was expired. A current sign-in in the official tool is needed; Weeklet deliberately does not renew it. |
| Real Codex Keychain-backed credential | This environment uses the official file-backed Codex credential. Keychain account derivation has isolated tests, not a live Keychain-backed Codex account test. |
| Interactive popover, outside click, keyboard and VoiceOver behavior | Desktop inspection timed out. Build, rendering and launch were verified; end-to-end interaction was not. |
| Launch at login and macOS approval flow | No system login item was enabled during development. Check after installing the app in Applications. |
| Intel execution and macOS 14 compatibility | The current machine is arm64 on macOS 26. The deployment target is 14; those hosts were not available. |
| Hosted macOS workflow | Included as a manual workflow; it has not been triggered. Local tests are the evidence for the reported passing result. |
| Developer ID signing and notarization | Requires the owner's Apple signing identity and notarization credentials. Local builds are ad-hoc signed only. |

## Reproduce

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/screenshots.sh
"build/Weeklet.app/Contents/MacOS/Weeklet" --check
```

The first command uses only synthetic test data. Screenshot generation also uses sample data and needs a macOS desktop session. The final command makes real read-only provider requests and exits 1 if either provider cannot report a weekly quota. Add `--allow-keychain` only for an explicit foreground Keychain access dialog.

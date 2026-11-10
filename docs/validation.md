# Validation record

Checked on November 9–10, 2026. The project is a local first version, not a notarized distribution release.

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
- **Tests:** 95 tests in six Swift Testing suites pass. The test script configures the framework and runtime search paths required by this standalone Command Line Tools installation. No XCTest dependency is needed.
- **Contract tests:** legacy and structured Claude weekly and session meters; Codex weekly quotas in either window position; missing, null, ambiguous and malformed data; percentage units and date formats; session-only responses, independent reset freshness and labeled menu summaries.
- **Credential tests:** expiry, API-key / ID-token rejection, redacted debug output, header injection, private read-only files, unsafe permissions, symlink refusal and storage-mode parsing. All fixtures are synthetic.
- **Service and state tests:** fixed HTTPS GET requests, provider-specific headers, redirect delegate refusal, no auth retry or token renewal, HTTP and network errors, Retry-After, independent providers, overlapping refreshes, manual throttling, wake checks and stale values.
- **Low-allowance countdowns:** synthetic clocks cover independent weekly/session reset labels, the displayed 20% threshold and rounding on both sides, hour/minute boundaries, the final minute, unknown resets, failed/outdated quotas and waiting for fresh usage after reset. Local countdown formatting does not call a provider or read credentials.
- **Provider visibility:** initial and loading states, authentication failures with previous usage, temporary failures without previous usage, cancellation, the zero-provider fallback, single-provider separators, and return after official-tool sign-in are covered with synthetic states and a controlled service. Hidden providers continue to be refreshed.
- **Update verification:** 17 isolated tests cover publisher signatures, modified payloads, metadata and archive limits, tampered digests, numeric version ordering, downgrade refusal, architecture/macOS requirements, fixed HTTPS hosts, traversal, duplicate paths, symlinks, malformed ZIP offsets, unsupported compression and private staging files. Release executables were checked for embedded personal build paths and passed code-signature verification.
- **Published releases:** the standard Ubuntu publishing workflow independently verified and published 1.1.0 and 1.1.1 on GitHub Releases. No private signing key, provider credential or personal access token was uploaded to the workflow.
- **Live update installation:** the real 1.1.0 installation displayed the 1.1.1 update banner. Clicking Update downloaded and authenticated the public GitHub package, prepared and replaced the bundle, and automatically reopened Weeklet. The installed 1.1.1 executable exactly matched the signed release archive and passed `codesign --verify --strict --deep`. The native popover showed live quotas and its installed-version footer after reopening.
- **Live Codex request:** the official usage endpoint returned HTTP 200. The weekly quota was in `primary_window`, with `limit_window_seconds = 604800` and null `secondary_window`. The compiled application also successfully reported the live Codex quota using its production transport and parser.
- **Claude expiry and recovery:** the existing Keychain item initially produced HTTP 401, and the compiled application reported **Session expired** without attempting renewal. After the user renewed the session in the official Claude Code tool, the production transport and parser successfully reported the real weekly quota and reset date. Weeklet did not modify a credential.
- **Activity tests:** lifecycle start/stop, final-answer and abort handling, sidechain exclusion, explicit-title selection, sanitized truncation, unchanged SQLite contents, stale activity expiry, Claude custom titles, coalesced checks, independent working counts, duplicate session IDs and completed-chat removal, numbered logo badges and inactive-pulse suppression use synthetic stores.
- **Live local activity:** the metadata-only reader detected ongoing local work and found explicit chat titles in the installed Codex and Claude Code stores. The diagnostic printed only working/idle flags and title lengths, not titles or conversation content.
- **Provider artwork:** the popover and menu bar use original provider-owned image files bundled locally. See `provider-artwork.md` for sources and checksums. The provider label is **Codex**.
- **Interface rendering:** the real SwiftUI popover was rendered at 2× scale with sample data and visually reviewed. Documentation images include both providers, a hidden expired provider, Help and the no-provider setup state. The preview substitutes only the AppKit menu control's ellipsis label because ImageRenderer cannot render that control.
- **Live desktop check:** the production app was opened with `--show` and left running without preview mode. Its actual native popover was inspected and showed current Claude Code and Codex percentages, available quotas, reset dates and an enabled Refresh button. The provider logos loaded with the build cache temporarily moved away, confirming the app uses its embedded resources.
- **Repository:** source, original image assets and documentation are stored in the public `mgalli97/weeklet` GitHub repository. No credentials, real account response fixtures or generated build caches are committed.

## Remaining manual verification

| Check | Why it remains |
| --- | --- |
| Real Codex Keychain-backed credential | This environment uses the official file-backed Codex credential. Keychain account derivation has isolated tests, not a live Keychain-backed Codex account test. |
| Help menu navigation, copy buttons, outside click, keyboard shortcuts and VoiceOver | Help and setup were rendered and visually reviewed with sample data. The real quota popover was inspected again on November 10, but the desktop inspector timed out when opening Options, so the complete interaction flow still needs a manual check. |
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

# Contributing to Weeklet

Keep the product small: a Mac-only menu bar utility, weekly quotas plus Claude's session quota, English text and an always-dark popover.

## Local workflow

1. Install Swift 6.0 or later with Apple's Command Line Tools or Xcode on macOS 14 or later.
2. Open `Package.swift` in your editor.
3. Run `./scripts/test.sh` for the isolated Swift Testing suite.
4. Run `./scripts/build.sh` for an optimized, ad-hoc signed app bundle.
5. Open `build/Weeklet.app` with `--preview` to review sample data without reading credentials.
6. Run `./scripts/screenshots.sh` from a macOS desktop session when updating the documented interface.

The application has no package dependencies. The test script handles the framework and runtime search paths needed by standalone Apple Command Line Tools. `swift test` from Xcode's toolchain also works with Swift Testing enabled; XCTest is not used.

## Changes worth testing

Cover new behavior at the contract or state boundary. Use synthetic, minimal fixtures; never paste a real provider response, access token, email, account identifier or Keychain export into a test, log or issue. Unit tests must not read the real credential store or call a provider.

When an endpoint changes, first confirm its current contract using provider documentation or a redacted read-only observation. Record the evidence and limitations in `docs/provider-contracts.md`. Add a fixture for the changed shape and ensure missing or ambiguous weekly buckets still fail closed.

Do not add token refresh, credential persistence, browser-cookie access, login automation, analytics or a backend. Credential access must remain read-only, URLs fixed, TLS validation enabled and all redirects refused.

## Review checklist

- Build and tests pass on macOS.
- Percentage units, weekly-window selection, missing resets and stale values remain explicit.
- Network and credential failures cannot leak server bodies or secrets.
- No unnecessary wakeup loop or animation runs continuously while idle; countdown updates exist only while a fresh zero-allowance reset is displayed.
- New UI stays compact, accessible, English and dark.
- Update screenshots and relevant documentation when behavior changes.

The repository includes a manually triggered macOS verification workflow. It does not automatically spend hosted macOS runner minutes on every push. No real provider credentials belong in CI.

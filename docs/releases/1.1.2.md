# Weeklet 1.1.2

Claude access recovery is now explicit instead of disappearing from the menu.

- Keep expired usage access visible with dashes and concise recovery guidance. Open Claude Code, then refresh; sign in again only if Claude Code asks.
- Keep a previously connected provider visible when Keychain access is lost. Missing, unsupported and unsafe credentials remain hidden.
- Pick up renewed access when opening the popover or waking after 30 seconds, without extra timers or healthy-provider requests.
- On a Claude HTTP 401, reread the local credential once and retry only if the official tool already changed its access token. No token is renewed, saved or modified.
- Preserve stale-data protections, five-minute refreshes, Retry-After and Codex behavior.
- Fix the test script for full Xcode with macOS Bash as well as standalone Command Line Tools.

Verified with 102 synthetic tests. Native Apple Silicon build, signed release verification and live read-only expiry/Codex checks completed. Automatic provider renewal is intentionally owned by the official tools.

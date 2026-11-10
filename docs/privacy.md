# Privacy and credentials

Weeklet only reads an existing subscription sign-in. Sign in using the official Claude Code or Codex tool first. It does not run either CLI, open a login flow, renew access, log out, modify an authentication file, change a Keychain item or save a token. Refresh tokens are not modeled or used. Expiration must be handled by the official tool, then click Refresh.

Missing, expired or unreadable sign-ins hide that provider from the menu bar and quota list. Options → Help shows the official sign-in commands and the current recovery message, even for a hidden provider. Copy buttons copy only a fixed command to the local clipboard; the app never runs it. All providers remain eligible for normal refresh, so signing in through the official tool is detected without restarting Weeklet. If none are ready, a Weeklet icon keeps Help reachable. No provider preference, session or setup history is persisted.

**Claude Code:** reads the `Claude Code-credentials` generic-password item using Apple's Security framework, then the official `~/.claude/.credentials.json` fallback only when the item is absent. For a custom absolute `CLAUDE_CONFIG_DIR`, reads that directory's `.credentials.json`; custom directory Keychain service names are not guessed or enumerated. This prevents accidentally reading another account. Custom-directory Keychain-only sign-ins are not currently supported.

**Codex:** respects the root `cli_auth_credentials_store` scalar in `CODEX_HOME/config.toml`, defaulting to `file`. Reads `auth.json` for `file`; the `Codex Auth` Keychain item for `keyring`; Keychain then file for `auto`; reports unavailable for `ephemeral`. The keychain account is `codex-` plus the first 16 hexadecimal characters of SHA-256 of the canonical Codex home path. `CODEX_HOME` defaults to `~/.codex`. Only the root storage scalar is parsed; this is not a general TOML parser. API-key-only and externally held sessions are unsupported.

Environment overrides must be absolute paths and present in the app's environment. Finder-launched apps do not inherit shell profile variables. To use an override, run the bundle executable from a terminal with that variable set. There is no credential picker, browser-cookie access, credential-helper execution or automatic search of other accounts.

Background refresh never requests Keychain interaction. If macOS denies access, unlock Keychain and click Refresh; a user-initiated refresh permits the system's Keychain dialog. Choose **Allow** for a single read if you do not want macOS to remember an access decision. Weeklet itself never updates Keychain access controls. A locked or denied item does not silently fall back to a different credential source.

Credential files must be regular files owned by the current user, with no group or other permissions. Reads refuse final-component symlinks, non-regular files and files over 1 MiB. No permission fixes are made automatically. Access tokens exist transiently in process memory and HTTPS request headers; Swift/Foundation cannot guarantee secure memory zeroing. Tokens, account IDs, response bodies and emails are never logged or persisted by Weeklet.

Provider requests are `GET` only, to two fixed HTTPS URLs. Every provider redirect is refused, including redirects on the same host. System TLS validation remains enabled. The ephemeral network session has no cookies, disk cache or credential storage. Responses are limited to 1 MiB and requests have 15/20-second timeouts. There is no configurable proxy or base URL inside the app; macOS networking settings still apply. The application is not App Sandbox enabled because it reads the official tools' local credentials; no broad entitlements are added.

## Updates

Opening the popover can request public release metadata from GitHub through a separate session with no cookies, credentials or Authorization header. As with any HTTPS request, GitHub sees the connecting IP address and the generic Weeklet user agent. No provider account, quota, token, chat title or conversation content is included. GitHub HTTPS redirects are restricted to its release hosts, and signed metadata pins the archive URL to this repository.

Clicking Update downloads a bounded signed package to a private temporary directory. A bundled installer verifies it again, replaces the app and reopens it. The only subprocesses are the bundled installer and system packaging/signature tools; no provider CLI or authentication helper is launched. The separate owner-only release tool reads its own `Weeklet Release Signing` Keychain item to sign publications. That key is unrelated to provider sessions, is never included in the app and is never sent to GitHub. See [updates](updates.md).

## Provider contract boundaries

See [provider contracts](provider-contracts.md) for exact request and response shapes.

## Local chat activity

An active chat's short title is intentionally displayed locally. Existing Codex SQLite metadata and bounded Claude Code/Codex transcript tails supply lifecycle signals. No activity hooks or helper processes are installed, and no title, message or activity history is transmitted or persisted. The indicator is best-effort and independent of provider quota requests. See [local activity](local-activity.md) for exact read boundaries and limitations.

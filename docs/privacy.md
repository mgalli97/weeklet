# Privacy and credentials

Weeklet only reads an existing subscription sign-in. Sign in using the official Claude Code or Codex tool first. It does not run either CLI, open a login flow, renew access, log out, modify an authentication file, change a Keychain item or save a token. Refresh tokens are not modeled or used. Expiration must be handled by the official tool, then click Refresh.

**Claude Code:** reads the `Claude Code-credentials` generic-password item using Apple's Security framework, then the official `~/.claude/.credentials.json` fallback only when the item is absent. For a custom absolute `CLAUDE_CONFIG_DIR`, reads that directory's `.credentials.json`; custom directory Keychain service names are not guessed or enumerated. This prevents accidentally reading another account. Custom-directory Keychain-only sign-ins are not currently supported.

**Codex:** respects the root `cli_auth_credentials_store` scalar in `CODEX_HOME/config.toml`, defaulting to `file`. Reads `auth.json` for `file`; the `Codex Auth` Keychain item for `keyring`; Keychain then file for `auto`; reports unavailable for `ephemeral`. The keychain account is `codex-` plus the first 16 hexadecimal characters of SHA-256 of the canonical Codex home path. `CODEX_HOME` defaults to `~/.codex`. Only the root storage scalar is parsed; this is not a general TOML parser. API-key-only and externally held sessions are unsupported.

Environment overrides must be absolute paths and present in the app's environment. Finder-launched apps do not inherit shell profile variables. To use an override, run the bundle executable from a terminal with that variable set. There is no credential picker, browser-cookie access, credential-helper execution or automatic search of other accounts.

Background refresh never requests Keychain interaction. If macOS denies access, unlock Keychain and click Refresh; a user-initiated refresh permits the system's Keychain dialog. Choose **Allow** for a single read if you do not want macOS to remember an access decision. Weeklet itself never updates Keychain access controls. A locked or denied item does not silently fall back to a different credential source.

Credential files must be regular files owned by the current user, with no group or other permissions. Reads refuse final-component symlinks, non-regular files and files over 1 MiB. No permission fixes are made automatically. Access tokens exist transiently in process memory and HTTPS request headers; Swift/Foundation cannot guarantee secure memory zeroing. Tokens, account IDs, response bodies and emails are never logged or persisted by Weeklet.

Requests are `GET` only, to two fixed HTTPS URLs. Every redirect is refused, including redirects on the same host. System TLS validation remains enabled. The ephemeral network session has no cookies, disk cache or credential storage. Responses are limited to 1 MiB and requests have 15/20-second timeouts. There is no configurable proxy or base URL inside the app; macOS networking settings still apply. The application is not App Sandbox enabled because it reads the official tools' local credentials; no broad entitlements are added.

## Provider contract boundaries

See [provider contracts](provider-contracts.md) for exact request and response shapes.

## Local chat activity

An active chat's short title is intentionally displayed locally. Existing Codex SQLite metadata and bounded Claude Code/Codex transcript tails supply lifecycle signals. No hooks or helper processes are installed, and no title, message or activity history is transmitted or persisted. The indicator is best-effort and independent of provider quota requests. See [local activity](local-activity.md) for exact read boundaries and limitations.

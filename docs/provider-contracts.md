# Provider contract evidence

Checked on November 9, 2026. The application and tests are original implementations; no application code was copied from another repository. Research was limited to official documentation, provider-owned issue reports, contract literals in the locally installed official CLIs and read-only endpoint probes. No competitor repository was fetched.

## Official references

- [OpenAI authentication](https://learn.chatgpt.com/docs/auth): local file / OS credential stores, `CODEX_HOME`, storage modes and subscription versus API-key authentication.
- [OpenAI app-server rate limits](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt): used percentages, window durations, reset timestamps and multiple rate-limit buckets. Its camelCase JSON-RPC objects are not the HTTP endpoint's snake_case wire contract. Weeklet does not launch app-server, which can manage or refresh authentication.
- [Claude Code authentication](https://code.claude.com/docs/en/authentication#credential-management): macOS Keychain, fallback credential file and per-directory credentials.
- [Provider-owned Claude Code issue #73770](https://github.com/anthropics/claude-code/issues/73770): reports current `limits[]` meter kinds, `weekly_all` versus `weekly_scoped`, percentage units and ISO reset dates. Issue comments are corroborating observations, not an official API guarantee.
- [Apple login-item service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp): native registration for the containing app.

## Local verification

The installed Codex CLI contains the `/wham/usage` endpoint family, `Codex Auth` service name and `limit_window_seconds` / `used_percent` / `reset_at` contract literals. The installed Claude Code 2.1.309 contains the `/api/oauth/usage` path, `oauth-2025-04-20` beta value, `claudeAiOauth`, `weekly_all` and `seven_day` literals. Only contract identifiers were inspected; implementations were not copied.

A live `GET https://chatgpt.com/backend-api/wham/usage` using the existing Codex subscription access token returned **HTTP 200**. Its `rate_limit.primary_window.limit_window_seconds` was **604800** and `secondary_window` was null. `used_percent` and `reset_at` were numeric. This directly established why selecting the secondary window unconditionally would be incorrect. Personal response fields and values were not saved as fixtures.

A live `GET https://api.anthropic.com/api/oauth/usage` initially returned **HTTP 401** for the existing Claude Code Keychain credential. No refresh was attempted by Weeklet. After the user renewed the session in the official Claude Code tool, a second check through the compiled application's production transport and parser successfully reported the real weekly quota and reset date. Both providers are therefore verified with live read-only requests. Personal quota values and account fields are not saved as fixtures or published in this repository.

The exact Keychain account derivation for Codex is supported in the implementation but was not exercised against a real Keychain-backed Codex account in this file-backed environment. Custom Claude Keychain names are deliberately unsupported until verified. No login item was enabled during development.

## Compatibility boundaries

These HTTP endpoints are internal account metadata services. Public documentation does not promise third-party compatibility. The implementation does not interpret a missing quota as unlimited, use API billing credits as weekly usage, sum model buckets, infer reset dates, refresh tokens or follow a new endpoint. An unsupported response produces an explicit error until its contract is reviewed.

## Claude five-hour session

The same usage response supplies the session quota, so displaying it adds no new request or timer. Weeklet selects `limits[]` with `kind == "session"`, reading 0–100 `percent` and ISO 8601 `resets_at`; without the structured array, it reads legacy `five_hour.utilization` and `five_hour.resets_at`. Weekly and session values remain separate, labeled `w` and `h` in the menu bar.

A subsequent read-only HTTP 200 probe verified that the current account response includes both `limits[]` and a `five_hour` object with numeric `utilization` and string `resets_at`. A missing session is unavailable; it is never synthesized as zero or substituted for the weekly quota. Some plans may not expose a five-hour limit. [Claude's official usage guide](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work) describes session and weekly limits as separate windows.

## Claude access expiry and rotation

Checked again on November 11, 2026. A read-only local metadata check confirmed that the existing Claude access token had expired; the production parser correctly refused it before networking, while Codex usage still succeeded. Personal expiry timestamps and token contents were not saved. This is access-token expiry, not evidence of an explicit logout. The official tool owns renewal; Weeklet never executes a provider CLI or uses a refresh token.

[Claude credential management](https://code.claude.com/docs/en/authentication#credential-management) documents Keychain storage and official login renewal. [Provider-owned issue #94491](https://github.com/anthropics/claude-code/issues/94491) reports Keychain access grants being lost during token rotation. That report is a possible additional cause of periodic access errors, not a confirmed cause on this machine. Weeklet preserves recovery guidance for known connections and permits a Keychain prompt only on an explicit manual refresh.

Claude Desktop can keep an embedded Claude Code session working while the separately stored CLI access token is expired. [Provider-owned issue #94464](https://github.com/anthropics/claude-code/issues/94464) describes this distinction and stale Keychain state. An active Desktop chat does not prove the credential visible to a separate read-only utility has renewed. Weeklet does not inspect another process's memory or environment, browser cookies or Desktop session databases to bypass that boundary.

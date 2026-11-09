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

A live `GET https://api.anthropic.com/api/oauth/usage` using the existing Claude Code Keychain item returned **HTTP 401**. The item was readable, but that credential was not valid for this request. No refresh was attempted. A successful authenticated Claude response could therefore not be verified in this environment. Its supported response shapes are based on the official installed CLI's contract identifiers and provider issue observations, and remain covered by synthetic tests rather than a successful live response.

The exact Keychain account derivation for Codex is supported in the implementation but was not exercised against a real Keychain-backed Codex account in this file-backed environment. Custom Claude Keychain names are deliberately unsupported until verified. No login item was enabled during development.

## Compatibility boundaries

These HTTP endpoints are internal account metadata services. Public documentation does not promise third-party compatibility. The implementation does not interpret a missing quota as unlimited, use API billing credits as weekly usage, sum model buckets, infer reset dates, refresh tokens or follow a new endpoint. An unsupported response produces an explicit error until its contract is reviewed.

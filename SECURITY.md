# Security

Weeklet's credential boundary is deliberately narrow: read an existing official-tool session, make a usage-only request, and discard the request context. There is no login, token renewal, writeback, token database or telemetry pipeline.

## Reporting

Report suspected credential disclosure or authentication-boundary issues privately to the repository owner through an existing private channel. Do not open a public issue containing credentials, provider response bodies, account identifiers or Keychain exports. Use synthetic examples in reports and redact local paths when they identify an account.

## Boundaries

- Provider access uses only `SecItemCopyMatching`; no provider credential is written. The separate publisher setup tool can create Weeklet's own update-signing key in Keychain. The app and installer never read that private key.
- Credential files are opened read-only, with final-component symlinks refused, ownership and permissions checked, and size bounded.
- Authorization is sent only to the two fixed provider HTTPS endpoints.
- Redirects are refused, including same-host redirects. The default system TLS trust policy remains enabled.
- Requests use an ephemeral session without cookies, URL cache or credential storage. Responses are bounded to 1 MiB.
- Background reads disallow Keychain interaction. A manual refresh may ask macOS to grant a single read. The app does not change an item's access controls.
- Tokens, account IDs and provider response bodies are never included in app logs, errors or persisted app state. Activity titles are intentionally shown only in local UI; documentation screenshots use synthetic titles.
- The app has no third-party runtime packages, backend, analytics or embedded browser.

## Update boundary

Updates use an independent credential-free GitHub HTTPS session. A pinned Ed25519 key verifies the small manifest before trusting its metadata; exact size, SHA-256, archive structure, app identity and code signature are checked before installation. Downloads are bounded and cannot substitute another repository, an older version or an incompatible architecture. The installer revalidates the package and prepares it before the main app quits. It performs an atomic same-directory swap and attempts rollback if reopening fails.

The dedicated installer runs only after an explicit Update action. It calls the system `ditto` and `codesign` tools, never a shell or provider CLI. The app does not disable Gatekeeper, remove quarantine, request administrator privileges or change system security settings. Publisher authenticity is established by the pinned update key, not by an Apple Developer ID: the free GitHub distribution uses ad-hoc code signatures and is not notarized. See [update security and publishing](docs/updates.md).

## Limitations

The app intentionally reads official-tool credentials outside the App Sandbox. It assumes the current macOS user account and OS networking stack are trusted. The OS may remember a Keychain access choice if the user selects that option. Swift/Foundation cannot guarantee zeroing every transient copy of a token in memory. The internal provider endpoints are not stable public API commitments.

An ad-hoc signature supports a local build; it is not Apple notarization or an independent security audit. Review [privacy and credentials](docs/privacy.md), [provider contracts](docs/provider-contracts.md), and [validation](docs/validation.md) for the precise supported behavior and remaining checks.

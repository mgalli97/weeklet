# Security

Weeklet's credential boundary is deliberately narrow: read an existing official-tool session, make a usage-only request, and discard the request context. There is no login, token renewal, writeback, token database or telemetry pipeline.

## Reporting

Report suspected credential disclosure or authentication-boundary issues privately to the repository owner through an existing private channel. Do not open a public issue containing credentials, provider response bodies, account identifiers or Keychain exports. Use synthetic examples in reports and redact local paths when they identify an account.

## Boundaries

- Only `SecItemCopyMatching` is used; no Keychain write APIs are present.
- Credential files are opened read-only, with final-component symlinks refused, ownership and permissions checked, and size bounded.
- Authorization is sent only to the two fixed provider HTTPS endpoints.
- Redirects are refused, including same-host redirects. The default system TLS trust policy remains enabled.
- Requests use an ephemeral session without cookies, URL cache or credential storage. Responses are bounded to 1 MiB.
- Background reads disallow Keychain interaction. A manual refresh may ask macOS to grant a single read. The app does not change an item's access controls.
- Tokens, account IDs, server response bodies and emails are never included in app logs, errors, screenshots or persisted app state.
- The app has no third-party runtime packages, backend, analytics, automatic updater or embedded browser.

## Limitations

The app intentionally reads official-tool credentials outside the App Sandbox. It assumes the current macOS user account and OS networking stack are trusted. The OS may remember a Keychain access choice if the user selects that option. Swift/Foundation cannot guarantee zeroing every transient copy of a token in memory. The internal provider endpoints are not stable public API commitments.

An ad-hoc signature supports a local build; it is not Apple notarization or an independent security audit. Review [privacy and credentials](docs/privacy.md), [provider contracts](docs/provider-contracts.md), and [validation](docs/validation.md) for the precise supported behavior and remaining checks.

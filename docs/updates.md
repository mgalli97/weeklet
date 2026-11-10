# GitHub updates

Weeklet is distributed directly from this repository's **GitHub Releases**. It does not use the App Store, a private backend, a paid Apple developer account, a third-party updater package or a GitHub account inside the app.

## Install

Download `Weeklet-macOS-arm64.zip` from the [latest release](https://github.com/mgalli97/weeklet/releases/latest), extract it and move `Weeklet.app` to a writable Applications folder. The first published binaries support Apple Silicon and macOS 14 or later. Intel users can build from source; the updater refuses incompatible architecture downloads.

Builds are ad-hoc signed and are not notarized by Apple. macOS may require the owner to approve the first launch. Weeklet does not disable Gatekeeper, remove quarantine attributes or change system security settings.

## In the app

Opening the popover checks for an update when due. Checks are coalesced and cached in memory; there is no update polling timer. **Options → Check for Updates** requests a manual check. A newer compatible release adds a compact **Version … available / Update** row. Installation happens only after the user clicks Update.

The download is verified, a separate installer prepares the replacement, then Weeklet quits and reopens. The old app stays running until preparation succeeds. The installer swaps the old and new bundles atomically in the same parent directory. It keeps the old bundle until reopening succeeds and attempts rollback if reopening fails. A non-writable installation location is reported rather than requesting administrator access.

## Trust boundary

- A fixed GitHub Releases URL supplies a small JSON envelope. Its payload is authenticated with Ed25519 before any version or download metadata is trusted.
- The public verification key is pinned in `UpdateTrust`. The app and installer never read the private signing key.
- Signed metadata binds the version, monotonically increasing build, minimum macOS, architecture, exact repository download URL, source commit, byte count and SHA-256 of the archive.
- Both marketing version and build must increase. A signed older or equal version cannot replace the installed app.
- Update HTTPS requests use a separate ephemeral session with no cookies, cached credentials or Authorization header. Redirects are restricted to GitHub's HTTPS release hosts. Provider tokens and account identifiers never enter this session.
- Manifests are limited to 64 KiB and archives to 64 MiB. The ZIP validator rejects traversal, extra roots, duplicate/case-colliding paths, symlinks, encrypted entries, ZIP64, unsupported compression, inconsistent local names, invalid offsets and expanded totals over 256 MiB.
- Extraction only occurs after signature, size, digest and archive-structure verification. The installer repeats verification, validates the expected app identifier and version, and checks the bundle's macOS code signature before replacement.
- Staging uses owned, private temporary directories and read-only, no-follow file reads. The app's installed provider credentials are not changed by an update.

The ad-hoc code signature checks integrity; it is not an Apple identity endorsement. Publisher authenticity comes from the separately pinned Ed25519 key. This implementation has isolated tests and local validation, not an independent security audit.

## Publish a version

The owner signs releases on a Mac. The private key stays in the login Keychain under service `Weeklet Release Signing`, account `com.mgalli97.weeklet.ed25519`. Never print or commit it, upload it to GitHub or put it in an environment variable. Back up the owner's Keychain securely: losing this key requires a manually installed trust migration.

`scripts/create-update-key.swift` creates the separate signing key only if absent and prints its public key. It is a publisher setup tool, never part of app startup. Existing clients pin the current key; do not replace it casually. Forks must use their own repository and key.

1. Update both version fields in `Resources/Info.plist`. Add `docs/releases/VERSION.md` with English release notes.
2. Commit the source. The release script requires a clean working tree and binds the manifest to that commit.
3. Run `./scripts/release.sh --prepare` to build, test, package and sign locally. It prepares `build/release` without replacing a running installation.
4. Run `./scripts/release.sh --publish` to push a `release-staging/vVERSION` branch using your normal Git authentication. It uses a separate index and leaves the source branch unchanged.
5. The **Publish signed release** workflow independently verifies the public signature, archive, app metadata and source commit, then publishes the ZIP and `update.json` as a GitHub Release. The tag points at the source commit, not the staging commit.

The staging branch contains only public release material in addition to the source. It may be removed after publication. The signing key is never sent to Actions; its short-lived built-in token only publishes the already-signed files in this repository. No personal access token or provider credential is required in CI.

GitHub's [standard hosted runners are free for public repositories](https://docs.github.com/en/billing/concepts/product-billing/github-actions), and [Releases host downloadable assets](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases). The publishing workflow uses a standard Ubuntu runner. No scheduled workflow, custom server, larger runner or paid Apple service is needed.

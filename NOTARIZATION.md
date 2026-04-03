# macOS Notarization

This fork maintains an automated notarization workflow for Mactrix releases. When triggered, it downloads the release asset from [viktorstrate/mactrix](https://github.com/viktorstrate/mactrix), signs it with an Apple Developer ID certificate, notarizes it with Apple, and uploads the result as a build artifact.

## Example: v0.1.0

The v0.1.0 release has been notarized as a proof of concept. The notarized DMG is available as a build artifact from the [Notarize workflow](https://github.com/beezly/mactrix/actions/workflows/notarize.yml) — download `Mactrix-notarized-v0.1.0.dmg` from the latest successful run.

This DMG is signed with **Developer ID Application: Andrew Beresford (4ZDNN637A8)** and will install on macOS without any Gatekeeper warnings.

## How it works

1. The workflow downloads `Mactrix.app.zip` from the upstream release
2. Signs the `.app` with a Developer ID Application certificate
3. Packages it into a DMG
4. Submits the DMG to Apple's notarization service
5. Staples the notarization ticket to the DMG
6. Uploads the result as a GitHub Actions artifact (retained for 14 days)

## Triggering automatically on new releases

To have notarization run automatically whenever a new release is published in `viktorstrate/mactrix`, two things are needed:

### 1. Add a secret to viktorstrate/mactrix

In the upstream repo: **Settings → Secrets and variables → Actions → New repository secret**

- **Name:** `NOTARIZE_DISPATCH_TOKEN`
- **Value:** *(provided separately — a fine-grained PAT scoped to Actions: write on beezly/mactrix only)*

### 2. Add a workflow file to viktorstrate/mactrix

Create `.github/workflows/notify-notarize.yml`:

```yaml
name: Trigger notarization

on:
  release:
    types: [published]

jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger notarization in beezly/mactrix
        run: |
          curl -X POST \
            -H "Authorization: token ${{ secrets.NOTARIZE_DISPATCH_TOKEN }}" \
            -H "Accept: application/vnd.github.v3+json" \
            https://api.github.com/repos/beezly/mactrix/dispatches \
            -d "{\"event_type\":\"notarize\",\"client_payload\":{\"tag\":\"${{ github.event.release.tag_name }}\",\"repo\":\"viktorstrate/mactrix\"}}"
```

When a release is published, this sends a `repository_dispatch` event to this fork with the release tag, which triggers the notarize workflow automatically.

## Triggering manually

The workflow can also be triggered manually via **Actions → Notarize → Run workflow**, with:

- **tag** — the release tag to notarize (e.g. `v0.1.0`)
- **repo** — the upstream repo (default: `viktorstrate/mactrix`)

## Credentials

All Apple credentials are stored as secrets in this repository and never touch the upstream repo:

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 export |
| `APPLE_KEY_ID` | App Store Connect API key ID |
| `APPLE_KEY_P8` | App Store Connect API private key (.p8) |
| `APPLE_ISSUER_ID` | App Store Connect issuer UUID |

The `NOTARIZE_DISPATCH_TOKEN` held by the upstream repo is a fine-grained PAT with **Actions: write** permission scoped to this fork only — it cannot read or modify any code or secrets.

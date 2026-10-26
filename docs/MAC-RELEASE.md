# Mac release packaging

The Mac menu bar app ships as a Developer ID signed, notarized download on
GitHub Releases. The flow follows the adjacent Valuz desktop release: pushing a
version tag builds, signs and notarizes on CI, then publishes the release with
English notes. Unlike Valuz, artifacts go to GitHub Releases rather than a CDN,
there is no auto-update feed, and one universal build covers Apple silicon and
Intel.

## Release a version

1. Add English release notes at `docs/releases/vX.Y.Z.md` and merge them to
   `main`. The workflow refuses a tag without notes.
2. Tag the merged commit and push the tag:

   ```sh
   git tag vX.Y.Z origin/main
   git push origin vX.Y.Z
   ```

3. The **macOS release** workflow runs `scripts/verify.sh`, packages with
   `--notarize`, and creates the `vX.Y.Z` GitHub Release with
   `CmuxRemote-X.Y.Z.dmg`, `CmuxRemote-X.Y.Z.zip` and `SHA256SUMS.txt`.

The marketing version comes from the tag; the build number is the workflow run
number. To produce signed, notarized artifacts without publishing, dispatch the
workflow manually with a version; the files are kept as a 7-day run artifact.

## What packaging does

`scripts/package-macos.sh`:

- builds the app and the bundled `cmux-remote` helper as universal
  (`arm64 x86_64`) Release binaries and rejects either if it is single-arch or
  requires a macOS newer than 14.0;
- signs inside-out with the hardened runtime and a secure timestamp, by
  certificate SHA-1 rather than name;
- verifies the Developer ID authority, runtime flag, timestamp and absence of
  `get-task-allow` on both binaries;
- notarizes the app, staples it, checks Gatekeeper, then builds the zip and DMG;
- signs, notarizes and staples the DMG and writes `SHA256SUMS.txt`.

Notarization status must be `Accepted`; otherwise the notary log is printed and
the run fails. Notary credentials are checked before the build starts.

## Credentials

`scripts/with-macos-signing.py` imports the P12 into a temporary keychain,
requires exactly one valid Developer ID Application identity there, passes its
SHA-1 to packaging and deletes the keychain afterwards. Nothing secret is
printed.

These are secrets of the `testflight` GitHub environment, which only `main` and
`v*` tags may use.

| Secret | Purpose |
| --- | --- |
| `CMUX_REMOTE_MAC_CERT_P12_B64` | Developer ID Application (G2) certificate, private key and G2 intermediate |
| `CMUX_REMOTE_MAC_CERT_PASSWORD` | P12 password |
| `CMUX_REMOTE_IOS_API_KEY_B64`, `_KEY_ID`, `_ISSUER` | App Store Connect API key, reused for `notarytool` |

The Developer ID certificate is issued to the owner team `7G42499LWB`. Creating
one requires the Account Holder. Keep the private key and P12 outside Git.

## Local packaging

`scripts/package-macos-local.sh` runs the same signing and packaging with local files instead of the
Base64 secret bundle:

```sh
scripts/package-macos-local.sh \
  --p12 /path/developer-id.p12 --p12-password-file /path/developer-id.p12.password \
  --notary-key /path/AuthKey_XXXX.p8 --notary-key-id XXXX \
  --notary-issuer ISSUER-UUID --version=0.1.0 --build-number=1 --notarize
```

Every path is absolute and read only by `scripts/with-macos-signing.py`, which imports the certificate
into a throwaway keychain and deletes it afterwards; nothing secret is printed. The flags have
`CMUX_REMOTE_MAC_CERT_P12_PATH`, `CMUX_REMOTE_MAC_CERT_PASSWORD_PATH`, `CMUX_REMOTE_NOTARY_KEY_PATH`,
`CMUX_REMOTE_NOTARY_KEY_ID` and `CMUX_REMOTE_NOTARY_ISSUER` as environment equivalents.

Omit `--notarize` for a signed but unnotarized local build; Gatekeeper will
reject it on other Macs. Artifacts are written to `.build/macos-release/dist`.
Development builds still use `scripts/build-macos.sh` and `scripts/install-macos.sh`.

# iOS TestFlight packaging

This repository follows the adjacent Valuz app's Fastlane approach: an existing
Apple Distribution certificate, an App Store provisioning profile, Release
archive/export, and App Store Connect API-key authentication. The app remains
independent of cmux and Valuz accounts. The existing owner-team distribution certificate can be reused across apps.
Valuz’s API key, app record, and app-specific profiles are not reused. Unlike Valuz's React Native project, this native
Swift project needs neither CocoaPods nor an extension profile.

## Release identity

`ios/Release.json` supplies the generated Xcode project and Fastlane defaults:

| Setting | Value |
| --- | --- |
| Bundle ID | `cmux-remote.mobile` |
| Apple team | `7G42499LWB` (Huiyuan Jia, individual) |
| Marketing version | `0.1.0` |
| Phone display name | `Cmux Remote` |
| App Store Connect name | `Cmux Remote for Mobile` |
| App Store Connect app ID | `6827037964` |
| App Store profile name | `cmux-remote mobile App Store` |

A build number is required for every packaging run. Choose a new positive
integer for every upload. `--version` and `--build-number` override the defaults
without editing the generated project. The GitHub workflow derives a build
number from its run number and attempt unless an explicit one is provided;
when also uploading locally, coordinate the numbers to avoid reuse.

For a fork, update the bundle/team/app record in `Release.json` to your own identity. Do not use `io.valuz` or the
official cmux identity. `CMUX_REMOTE_IOS_TEAM_ID`, `CMUX_REMOTE_IOS_BUNDLE_ID`,
`CMUX_REMOTE_IOS_PROFILE_NAME` and `CMUX_REMOTE_IOS_OUTPUT` can override release
settings. If changing the bundle ID, also select its own profile name.

## Apple account prerequisites

1. Register this app's explicit Bundle ID in the configured Apple team.
2. Create a separate App Store Connect app record for that Bundle ID. Valuz's
   numeric App Store ID is unrelated and must not be reused.
3. Have an existing Apple Distribution certificate and private key exported as
   a password-protected P12. Fastlane fetches or creates this app's App Store
   provisioning profile; it never creates or revokes distribution certificates.
4. Use an App Store Connect API key authorized to manage provisioning and upload
   this app. Keep its P8 file and the P12 outside Git.

## Local packaging

Use Ruby 3.3+; the workflow pins Ruby 3.3.12 and Fastlane 2.238.0, matching Valuz.
Install the locked dependencies once:

```sh
cd ios
bundle install
cd ..
```

Inspect public release settings or compile a device archive without credentials:

```sh
scripts/package-ios.sh --build-number=1 --dry-run
scripts/package-ios.sh --build-number=1 --unsigned
```

The unsigned archive checks device Release compilation and bundled resources; it
cannot be installed through TestFlight or uploaded.

For signed export, use an already installed distribution certificate with these
variables supplied through your shell's secret manager:

- `CMUX_REMOTE_IOS_API_KEY_PATH`: absolute path to the P8 file.
- `CMUX_REMOTE_IOS_API_KEY_ID` and `CMUX_REMOTE_IOS_API_ISSUER`: API key identity.
- `CMUX_REMOTE_IOS_BUILD_NUMBER`: required, or pass `--build-number`.
- `CMUX_REMOTE_IOS_APP_STORE_APP_ID`: optional override of this app’s ID from `Release.json`.

```sh
scripts/package-ios.sh --version=0.1.0 --build-number=2
# Explicitly add --upload to submit the exported IPA to TestFlight.
scripts/package-ios.sh --version=0.1.0 --build-number=3 --upload
```

Alternatively, supply the five CI variables below and wrap the packaging command
with `python3 scripts/with-ios-signing.py`. It decodes the P8/P12 to private
temporary files, imports the existing certificate into its own temporary
keychain, restores the original search list, and deletes the temporary signing
material on exit. This wrapper serializes with the single CI packaging job;
do not run multiple wrappers concurrently on one local user keychain.

Outputs default to `.build/ios-release/`: the archive, DerivedData, and
`dist/CmuxRemote.ipa` plus dSYMs. The upload lane verifies the IPA's identity,
version/build, nonexpired App Store profile/team and actual code signature
before uploading. TestFlight upload skips waiting for processing and does not
automatically distribute to external testers or notify them.

## GitHub Actions

The release workflow pins Xcode 26.3 through `DEVELOPER_DIR` on the macOS 15
runner. Its default Xcode 16.4 lacks the iOS 26 native content-back API; a runtime
availability check does not make that declaration available to an older SDK.
The selection is validated before building and signing.

Create a `testflight` GitHub environment (or use repository secrets) and supply:

| Secret | Content |
| --- | --- |
| `CMUX_REMOTE_IOS_API_KEY_B64` | Base64-encoded P8 file |
| `CMUX_REMOTE_IOS_API_KEY_ID` | App Store Connect API key ID |
| `CMUX_REMOTE_IOS_API_ISSUER` | App Store Connect issuer ID |
| `CMUX_REMOTE_IOS_CERT_P12_B64` | Base64-encoded existing distribution P12 |
| `CMUX_REMOTE_IOS_CERT_PASSWORD` | P12 password |

Optionally set the environment/repository variable
`CMUX_REMOTE_IOS_APP_STORE_APP_ID` to this app's numeric App Store Connect ID.
Do not put secrets in `Release.json`, workflow YAML, logs, or command history.

In Actions, manually run **iOS TestFlight** with a marketing version, optional
build number and **Upload the signed IPA to TestFlight**. Upload defaults to
false; pushes and tags do not trigger this workflow. Both export modes require
the signing secrets. The workflow runs repository verification, imports signing
material temporarily, exports the IPA, and retains the IPA/dSYMs as
workflow artifacts for seven days. Artifact visibility follows the
repository's visibility and access settings.

The app icon and privacy manifest are included in the project generator. The
original generated icon and its prompt are documented in `ios/Resources/APP-ICON.md`. Export compliance declares the app's
OS-provided encryption through `ITSAppUsesNonExemptEncryption=false`; update
that declaration and the privacy manifest if the app's behavior changes.

## Verification boundary

Portable release checks run inside `scripts/verify.sh`: version/build validation,
refusal to upload an unsigned archive, wrong-app/version/path rejection, App
Store profile validation, and cleanup after a failed packaging command. A
successful unsigned archive or dry run does **not** establish signed export,
App Store Connect access, TestFlight processing or physical-device acceptance.
Those require this app's Apple record, actual credentials and a signed run.

## Activated owner configuration — 2026-10-12

The owner authorized a dedicated Developer API key and storage of the P8/P12
signing material in GitHub's `testflight` environment Secrets. The environment
is restricted to the `main` branch. Private key/certificate files are not
tracked in Git; the API key backup is outside the checkout with private file
permissions, and the temporary P12 export was removed after configuration.

`0.1.0 (1)` was uploaded successfully and Apple finished processing it. The
internal **Owner** group contains only the account owner; that tester is invited
and the build is **Ready to Test**. Accept Apple's TestFlight invitation on the
phone to install. No external tester group or public invitation link was created.

The full manual GitHub packaging job also passed on the app's current code:
[run 38249260373](https://github.com/St0neWan9/cmux-remote/actions/runs/38249260373).
That run exported `0.1.0 (2)` without uploading it. The downloaded CI IPA passed
the same identity/version, App Store profile and deep/strict code-signature
guards. Future uploads must use an unused build number.

## Checking build status locally

`scripts/testflight-status.py` lists the app's latest builds with their processing and
internal/external TestFlight state. It reads the same App Store Connect API key the release
uses, `~/.cmux-remote-release/huiyuanjia/notary.json` (`key_id`, `issuer_id`, `key_path` to an
owner-only `.p8`); `CMUX_REMOTE_ASC_CONFIG` names another. The key never enters this
repository. A key from the retired account sees none of this app's builds, so an empty list
means the wrong key. Uploads use `skip_waiting_for_build_processing`,
so a successful workflow means "uploaded", not "installable": wait until the build shows
`processing=VALID` and `internal=IN_BETA_TESTING`.

# Unified Mac menu bar application

## Product contract

UI tokens, component rules, density, states and interaction copy are defined in
[the Mac design system](DESIGN-SYSTEM.md). Apply that specification before laying
out the menu or settings pages.

Both the source Mac and viewing Mac install the same **CmuxRemote** menu bar
application (`~/Applications/CmuxRemote.app`). It can share this Mac and connect to other Macs at the same time.
The menu bar icon belongs to macOS. This is an independent application using the
official cmux APIs, not an ExtensionKit sidebar or an injected cmux settings page.
The official native sidebar, Remote workspace group, terminal mirroring, identity
checks, explicit enrollment approval, scoped grants and durable mutations retain
their current behavior. The phone UI and remote wire resources remain unchanged.

The app has no automatically opened main window or Dock icon. A missing first-use
cmux connection opens the one Settings window to explain setup. Its small menu
shows local sharing status, the pending approval count, **Remote Settings…** and
Quit. Settings is one reusable preference window. Its toolbar categories are
Share This Mac, Add Device, Devices, Connect to a Mac and Advanced; the two
product areas are:

- **Share This Mac**: sharing switch, endpoint/status, workspace selection for
  new pairing, expiring QR code, exact pending-device approval/denial and paired
  device revocation. Advanced connection information stays collapsed.
- **Connect to a Mac**: the existing nearby/saved host, trust, enrollment and
  workspace-mirror flow. Native Remote rows remain the everyday workspace entry.

Closing Settings leaves the background service and mirrors running. The resident remembers the owner's last explicit sharing choice
(`sharing.json`, owner-only) and restores it after a restart; a listener that ends
on its own is not recorded as "off". A failed restore is shown as a status error. Quitting the
menu bar app does not implicitly revoke devices or stop a separately running CLI
Bridge. A process started by this app is its own resource and can be stopped by
the app. No unrelated Bridge or official cmux process may be killed.

## Service ownership

Keep the CLI executable and shared Swift packages. Bundle the CLI in the Mac app
so installed users do not need a checkout or a PATH entry. The UI talks only to
the private owner Unix socket; host/device keys never move into URLs or argv.
An existing CLI Bridge is adopted through that socket, preserving its state.
New app-owned services use the same default private state and run lease.

Separate resident owner/discovery/mirror services from the HTTPS sharing
listener. Stopping **Share This Mac** closes enrollment, stops advertisement and
HTTPS, and leaves outgoing connections/native mirrors available. It preserves
host identity, certificate, approved-device registry and saved remote hosts.
Starting sharing binds the configured LAN port without issuing a new identity.
Listener errors appear as stable status codes. Port conflicts must not silently
change the advertised endpoint or leave a success switch enabled.

Add private owner methods for sharing status/start/stop and local workspace
inventory. Owner approval continues through the existing exact-request scope
validation. The public HTTPS enrollment, history and terminal resources are not
expanded. The existing `serve` CLI remains compatible; a resident mode permits
the menu bar app to control only the sharing listener.

## First connection to official cmux

After installing, click the CmuxRemote icon in the macOS menu bar and open
**Remote Settings…**. If no resident is available, copy its setup command into a
new cmux shell, run it once, then use **Retry Connection**. Setup changes neither
cmux settings nor its socket policy. A new installation creates private Bridge
credentials once; existing state and saved grants are retained.

Under **Share This Mac**, turn sharing on, choose the allowed workspaces and
click **Start Pairing**. Scan the five-minute QR on the phone, or select the
advertised host on another Mac. Check the requesting device's identity and
requested permissions, then approve or deny it in this same page. Devices stay
listed after approval and can be revoked individually. Ending pairing closes
new enrollment, while turning sharing off closes remote access.

Use **Connect to a Mac** for the existing discovery, saved hosts and mirror flow.
If an older CLI Bridge uses another state directory, select that exact directory
under **Advanced** and Apply; this changes which resident the UI controls, not
its identity or grants. An older resident without managed-sharing methods must
be upgraded explicitly. The app never kills it to take over its state.

The app must not change cmux socket policy. Under `cmuxOnly`, a process launched
by Finder cannot assume terminal ancestry. A one-time setup command run by the
user in a cmux shell transfers its official inherited socket capability and
socket path to an owner-only local file. The bundled Bridge presents the
capability through the official CLI. Do not scrape credentials, alter global
shell configuration, or paste commands into an arbitrary foreground terminal.
If the installed cmux cannot supply that capability, retain the supported
CLI-inside-cmux route and explain the concrete limitation.

The UI presents the fixed setup command and a Copy button only when required.
Normal app launches restore that setup. Validate the official connection before
claiming readiness. Capability/state failures do not select another socket or
weaken authentication. Existing externally started Bridges require no migration
of their paired state, and their stop/start UI is available after upgrading to
the managed-listener implementation.

## Verification

Behavioral tests cover listener start/stop/restart, bind failure, identity/grant
retention, owner-only administration, exact approval scope, revoked devices,
resident service survival while sharing is off, and setup file permissions.
Existing connection and mirror tests must keep passing.

Build and install only this project's app. Exercise the macOS menu, single
settings window, close/reopen, start/stop, QR display, request approval/denial,
revocation and saved/nearby Mac flows. Capture real screenshots of the menu and
both settings sections. Live checks use controlled existing source workspaces,
never restart Agents, and never replace or restart the official cmux app.

### Current evidence, 2026-10-13

- Verification of the isolated Mac PR passed: **208 Swift tests in 41 suites**. The
  existing phone guards ran as part of that script; this Mac UI task did not edit
  the phone UI. The final Mac localization audit passed with **98 matching
  English/Simplified Chinese keys**. Native app/helper builds and ad-hoc signature
  verification passed in the original working checkout during UI acceptance.
  The subsequent isolated native rebuild was stopped at the user’s request;
  no additional validation was performed before merging.
- The settings window now follows the supplied classic macOS preference reference:
  AppKit category toolbar, #ECECEC light background, 760 × 540 default frame,
  700 × 480 minimum frame, 13-point body / 11-point secondary text, right-aligned
  form labels, bordered system lists and standard buttons. Titles and primary
  actions stayed on one line in the actual minimum-size Chinese window.
- Actual installed-app UI acceptance exercised sharing on/off, workspace selection,
  QR generation/end pairing, full requesting identity/scope inspection, approval,
  denial, revocation with an exact-device confirmation, data-directory Apply,
  saved/nearby hosts, and the native workspace mirror action.
- A pinned test client decoded the actual screenshot QR and submitted a request
  for the controlled **Demo project** only. UI approval produced a validated
  scoped connection and exactly one readable workspace. UI revocation made its
  next read fail with `unauthorized`. A second request returned `denied` after
  the UI denial. No test clients retain access; test sharing and enrollment were
  closed afterward.
- Command-W closed Settings without stopping the resident/sharing service. Reopening
  the app reused Settings with the same live QR, selection and scroll position.
  The real state directory was restored after the Demo tests.
- The existing Alpha connection read the approved source workspace and the new
  UI mirror action reused its native mirror. Owner status reported `watching`
  with no error for the existing local workspace. Source Agents were not restarted
  or sent prompts. These are two independently running Bridge services on this
  Mac; this pass does not claim a new physical second-Mac acceptance.
- The UI pass found a real catalog regression: a returning remote workspace whose
  previous local mirror was closed could remain blocked as `outcome_unknown`.
  Two red/green regressions now permit replacement only after a confirmed seed,
  complete local-absence checks and fresh remote authority, while preserving
  genuinely uncertain creation intents. The focused catalog suite passed 13 tests.

Local screenshot evidence is saved under `.build/verification/menu-bar/`:
`17-final-sharing.png`, `18-final-connection.png`,
`14-reference-minimum-zh.png` and `16-reference-pairing-final-zh.png`.
These are actual app captures, not mockups. The screenshots are local verification
artifacts; private credentials and source terminal captures are not published.
The QR screenshot was decoded successfully by Vision (558-byte signed bootstrap).

The initial UI-tool failure was isolated to accessibility traversal of nested
SwiftUI GroupBox content. The final forms do not contain GroupBox; actual window
reads, clicks, screenshots and repeated close/reopen succeeded. UI acceptance is
no longer pending on that earlier tooling issue. Dark appearance and a fresh
English visual pass remain separate checks; locale-key parity is verified.

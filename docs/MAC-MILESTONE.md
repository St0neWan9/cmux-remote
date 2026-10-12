# Mac-to-Mac Alpha milestone

Reviewed on 2026-10-12. This thread covers the Mac Companion, Bridge and native
cmux workspace mirroring. Phone work is excluded.

## Target

On Mac A, keep an existing official cmux workspace and its Claude/Codex processes
running. On Mac B, discover and authorize A, select that workspace, and operate
its existing terminals from cmux's native Remote group. Local workspaces retain
their original sidebar. Disconnecting a mirror must leave source processes alive.
Neither Mac requires a cmux cloud account or a modified official cmux binary.
First-use identity confirmation and host approval remain explicit; a binding code
is not required for LAN discovery.

## Current milestone status

The implementation is a frozen **single-Mac integration candidate**, ready for
focused two-Mac validation. It is not yet an accepted two-Mac Alpha or a public
release. No additional feature work is required before the next acceptance pass.

| Core behavior | Evidence established |
| --- | --- |
| Native Remote group below local workspaces | Actual official cmux sidebar, native rows, inventory and lazy attachment |
| Existing producers and layout | Nested splits, pane tabs and six terminal viewers; no new remote Agent |
| Output and input | Character-grid snapshots and real terminal input; durable duplicate-operation check across Bridge restart |
| Source topology updates | Add, reorder and remove; retained viewer IDs and processes |
| Detach and authorization | Source survives detach; read-only input refusal and isolated client revocation |
| Rendering | Positioned repaint; recorded 110-frame clip with no blank header frames in the tested TUI |
| Recovery | Five local Bridge restarts and a 20-second remote Bridge outage; same viewer bindings/PIDs and resumed TUI frames |
| Scoped verification | Final 79 Mac-related tests in 12 suites; Mac/CLI builds; ad-hoc signature verification; 39 matching Mac locale keys |

See [acceptance receipts](ACCEPTANCE.md) and [operation guide](MAC-EXTENSION.md).
The test counts do not establish physical LAN or complete Agent UX acceptance.

## Three exit gates, in order

1. **Two physical Macs:** run the same candidate on A and B; verify discovery,
   identity confirmation, host approval and workspace selection. Show the native
   Remote group, output and input. Interrupt only the test Bridge/network path,
   restore it, and show that the source processes and local mirror survive.
2. **Real existing Agents:** exercise one Claude terminal and one Codex terminal
   already running on A. Verify output growth, one controlled input, interrupt,
   focus/tab switching and local detach; inspect the source for unintended input
   and verify the producer is unchanged. Record interaction latency and clipping
   at representative local pane sizes. Failures in this ordinary workflow block
   Alpha; do not claim acceptance from a synthetic TUI alone.
3. **Repeatable delivery:** install the frozen candidate into a clean test setup,
   follow the documented start/enroll/open steps, and repeat after a Companion
   and Bridge restart without another enrollment. Capture the full Mac journey
   and pin the exact accepted artifact/source revision. Keep unrelated phone edits
   out of milestone changes; do not commit the entire shared worktree blindly.

The existing paired-installation part of gate 3 passed on 2026-10-12: the frozen
Companion installed, restored saved hosts, opened six native viewers, and retained
them through repeated UI open, local Bridge restart and Companion cold launch.
The `alpha-01` through `alpha-05` screenshot sequence and
`alpha-installed-companion-flow.json` record it. Fresh enrollment and a clean
second-Mac installation remain unverified.

Only failures in these three gates expand the immediate implementation scope.
Physical two-Mac validation needs a second reachable test Mac; the current
receipts establish separate authenticated processes on one Mac.

## Alpha boundaries

Terminal output is a bounded character-grid snapshot, converted to ANSI, with a
300 ms viewer delay plus request time. It is not a screenshot and it can miss
changes between reads. The producer remains on A. This architecture does not
provide lossless PTY streaming, complete scrollback, graphics/browser mirroring,
clipboard integration, exact split proportions or shared producer resizing.

Use source-compatible pane sizes during Alpha. If lossless native terminal parity
is a core acceptance requirement, the public cmux interface gap must be resolved;
it cannot be closed by more snapshot tests.

Phone features, other operating systems, exhaustive endpoint roaming, additional
mode combinations, one-click daemon management and public release signing are
later milestones. The candidate uses ad-hoc debug signing; Developer ID signing
and notarization remain required for the planned public distribution workflow.

## Freeze and review

A private local review bundle is stored under
`.build/verification/milestone-mac-alpha/`. It contains the current CLI and Mac
Companion, the Mac guide, this milestone document, selected screenshots/receipts
and an artifact checksum manifest. It contains no Bridge state directories,
identity private keys or grants. The bundle is for local review, not publication.
The source checkout still contains concurrent uncommitted work, so a Git release
tag is not implied by this artifact freeze.

## Manual second-Mac handoff

Mac A's dedicated frozen source service and preflight passed. The owner will
perform Mac B's physical test using the Chinese
[LAN Alpha guide](LAN-ALPHA-TEST.zh-CN.md), including exact addresses, certificate
and package fingerprints, separate A/B commands, fresh enrollment and recovery
expectations. This is a handoff of the physical gate, not a completed two-Mac gate.

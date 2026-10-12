# Conversation presentation and timing

All iPhone screens use a white canvas. Conversation messages blur only their overlapping ink beneath the floating header; the composer keeps its established optical alignment. Pairing, files and pending actions use the same white surfaces and floating navigation. The scanner preserves its camera preview with white navigation chrome.

A completed response shows copy, share and quote-to-follow-up controls, plus its recorded completion time. Sharing opens the system share sheet; quoting only edits the local draft. Copy/share/quote contain all committed prose blocks in the final assistant record immediately above the footer, excluding earlier progress commentary. History preserves equal-sequence records, so pagination cannot split this action text. No action starts another agent or sends a provider request.

The bounded history snapshot has additive optional fields:

- `responses`: first/last message IDs and sequences, prompt start, completion flag, optional completion timestamp, optional duration and `recordedDuration`.
- `recordedRunSeconds`: sum of available recorded completed-turn durations throughout the bounded transcript, independent of the history page.
- `recordedTurnCount`: how many recorded turns contributed to that sum, including interrupted turns with no prose or no agent output.
- `currentTurnStartedAt` / `currentTurnCompleted`: source-stamped start and observed completion, independent of pagination and agent output. An unstamped prompt keeps the working indicator without inventing elapsed time.

Claude `system/turn_duration` records provide `durationMs`. Codex `task_started` and matching `task_complete`/`turn_aborted` lifecycle timestamps provide elapsed run duration. The Bridge reads only the same authorized complete JSONL records already used for history, skips Claude sidechains, and leaves the pinned upstream parser unchanged. A partial trailing record never supplies timing. Transcript replacement resets metadata with history generation.

Without explicit completion metadata, a following human prompt closes the previous response for presentation. Its duration is an **estimate** from explicitly stamped prompt and reply records, excluding the idle gap before the next prompt. Missing or invalid timestamps and durations remain unknown. Estimates are never counted as recorded running time. The unfinished latest response has no invented completion timestamp; its live counter describes elapsed turn time, not CPU time or billing usage. The conversation-time sheet explains that the cumulative number covers only recorded turns, not idle time or missing records.

Verification: `scripts/verify.sh`, `scripts/build-ios.sh`, and the task-owned Simulator conversation/files/feed/pairing navigation. Physical-camera enrollment, device GPU performance and finger-driven inertia remain device checks.

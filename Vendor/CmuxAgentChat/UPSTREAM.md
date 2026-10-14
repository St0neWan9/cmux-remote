# Upstream provenance

Source: https://github.com/manaflow-ai/cmux

Revision: `00aa07ba855b70bd7c4805ef1b8387b82f87fd63`

Original directory: `Packages/Shared/CmuxAgentChat/Sources/CmuxAgentChat`.

The 116 Swift source files retain upstream notices. The two parser initializers expose bounded text-budget parameters for explicit paginated tool-detail reads. TranscriptTextBudget counts Unicode scalars so a single oversized grapheme cannot bypass its bounds; default history limits retain their original numeric values. The prose screen extractor also steps over composer chrome — the input box's frame, its dividers and CLI notices such as `✔ Update installed · Restart to update` — instead of printing it as the agent's prose or stopping there and discarding the answer above it; the box side shares `│` with a prompt boundary, so chrome is recognised before the boundary glyphs. The Bash terminal capture also keeps the agent's one-line description of the command — what the terminal prints above it — instead of discarding it; a completion carries it through. A row carrying the CLI's git-branch marker (`⎇ main`) is chrome too: the branch is the working directory's state, never the agent's prose, and so is a row that is only a quoted absolute path — how a pasted file reaches the agent — while a row that merely mentions a path keeps its own words. These four local source patches are fixture-tested. The local package manifest omits the upstream test target because its test fixtures are not vendored. Original project copyright and GPL-3.0-or-later terms are preserved in `LICENSE`. No BUSL server directories are included.

This is a build-time source dependency, not a modification of the installed cmux application. Updates are deliberate and fixture-tested; they are not fetched at runtime.

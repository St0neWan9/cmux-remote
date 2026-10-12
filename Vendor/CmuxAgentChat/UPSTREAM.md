# Upstream provenance

Source: https://github.com/manaflow-ai/cmux

Revision: `00aa07ba855b70bd7c4805ef1b8387b82f87fd63`

Original directory: `Packages/Shared/CmuxAgentChat/Sources/CmuxAgentChat`.

The 116 Swift source files retain upstream notices. Two parser initializers have a local patch exposing bounded text-budget parameters for explicit paginated tool-detail reads; default history parsing keeps the original limits. The local package manifest omits the upstream test target because its test fixtures are not vendored. Original project copyright and GPL-3.0-or-later terms are preserved in `LICENSE`. No BUSL server directories are included.

This is a build-time source dependency, not a modification of the installed cmux application. Updates are deliberate and fixture-tested; they are not fetched at runtime.

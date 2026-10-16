# Upstream provenance

Source: https://github.com/gonzalezreal/textual

Release: `0.5.0`, revision `01b51875a5406eefc95f52a058cb059e7bc94dc4`.

Original directory: `Sources/Textual`. The Swift sources, `LICENSE` (MIT) and `LICENSE-3rdparty.csv` are copied unchanged apart from the two patches below. The local manifest omits the upstream test target and its snapshot-testing dependency; the remaining dependencies are pinned to the versions upstream resolved.

## Patches

Both are open upstream pull requests, applied in order on top of `0.5.0`. The exact diffs are kept in `Patches/`.

1. `0001-pr80-stale-text-positions.diff` — [#80](https://github.com/gonzalezreal/textual/pull/80), head `bd9fbee3d7`. Clamps text positions that outlive a content update, so a selection held while a reply streams in does not trap in `TextLayoutCollection` ([#87](https://github.com/gonzalezreal/textual/issues/87)).
2. `0002-pr88-selection-actions.diff` — [#88](https://github.com/gonzalezreal/textual/pull/88), head `9f4b100e58`. Adds `textual.textSelectionActions(_:prominence:)` for app items on the selection menu, restores the system's Look Up and Translate, and adds `textual.textSelectionCoordination()` so one selection holds across several texts.

With both applied, the upstream suite on an iOS 26.5 simulator runs 165 tests; the same two `BlockQuoteTests` snapshot comparisons fail as on unpatched `0.5.0` (pixel match 0.989 against 0.995, a rendering difference on this simulator), and the tests the patches add pass.

## Refreshing

When upstream releases with these pull requests merged, replace `Sources` from that release, drop the matching patch files, and update this note. Updates are deliberate; nothing is fetched at runtime.

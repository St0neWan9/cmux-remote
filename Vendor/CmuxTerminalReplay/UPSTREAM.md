# Upstream provenance

Source: https://github.com/manaflow-ai/cmux
Commit: `00aa07ba855b70bd7c4805ef1b8387b82f87fd63`
License: GPL-3.0-or-later; preserve upstream notices.

Selected Foundation-only render-grid DTO and VT replay sources copied without modification. The package name is local; no Ghostty binary or terminal engine is linked.

Local addition: `MobileTerminalGridViewport.swift` crops captured cells around the cursor for smaller desktop viewers and supports local row panning. It reuses the vendored cell-width rules and never resizes a source terminal. The upstream files remain unmodified.

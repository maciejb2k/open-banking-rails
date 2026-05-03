# 0007 - Chart library: Chart.js via importmap

## Context
Analytics needs bar + line charts. Stack is Rails 8 + `importmap-rails`,
no jsbundling, Stimulus-heavy frontend, Turbo navigation.

## Alternatives
- **Chart.js (ESM, importmap-pinned)** - ~70KB, tree-shakable.
- **ApexCharts** - ~150KB, prettier defaults, more chart types than
  MVP1 needs.
- **Chartkick** - Rails wrapper around Chart.js; pinning both under
  importmap is historically fragile.

## Decision
Chart.js, pinned to jsdelivr's `+esm` endpoint. The standard JSPM build
splits into multiple chunks (chart core + helpers + @kurkle/color)
which `importmap-rails` doesn't follow when downloading; jsdelivr's
`+esm` returns a pre-bundled single ESM that resolves its own deps via
absolute jsdelivr paths. Net effect: production fetches Chart.js from
the CDN at runtime, no vendor files. One Stimulus controller reads a
JSON config from a data attribute and instantiates the chart;
`disconnect()` calls `chart.destroy()` so Turbo nav doesn't leak
canvases.

## Consequences
- Production depends on cdn.jsdelivr.net at request time. Acceptable
  for a personal-app PFM; if dropped, vendor the `+esm` bundle
  (and hand-resolve the @kurkle/color URL inside it) or switch to UMD.
- All future charts go through the same controller - config is data,
  not JS. Plugins (datalabels, zoom) = extra remote pins, defer until
  needed.
- Drill-down lives at URL level (separate routes), not inside the
  canvas. Revisit if interactive complexity outgrows that - Chart.js
  custom tooltips with Turbo Frames get awkward.

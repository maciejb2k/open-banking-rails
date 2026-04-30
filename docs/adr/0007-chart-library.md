# 0007 — Chart library: Chart.js via importmap

## Context
Analytics views need bar charts (spend by category) and line/bar
charts (12-month merchant trends). Stack is Rails 8 + `importmap-rails`,
no jsbundling, Stimulus-heavy frontend, Turbo navigation.

## Alternatives
- **Chart.js (ESM, importmap-pinned)** — ~70KB, tree-shakable, plain
  ESM via JSPM, drop into a Stimulus controller.
- **ApexCharts** — ~150KB, prettier defaults, more chart types than
  needed for MVP1.
- **Chartkick** — Rails view-helper wrapper around Chart.js; pinning
  both Chartkick and Chart.js under importmap is historically fragile.

## Decision
Chart.js, pinned to `https://cdn.jsdelivr.net/npm/chart.js@4.5.1/+esm`
in `config/importmap.rb`. Standard JSPM/ESM builds split chart.js into
multiple chunks (helpers + chart core + @kurkle/color), which
importmap-rails doesn't follow when downloading. jsdelivr's `+esm`
endpoint returns a pre-bundled single ESM that resolves its own deps
via absolute jsdelivr paths — so the runtime fetches from CDN, no
vendor files needed.

One Stimulus controller (`chart_controller.js`) imports
`{ Chart, registerables }`, calls `Chart.register(...registerables)`
once on import, reads a JSON config from a data attribute, and
instantiates the chart. `disconnect()` calls `chart.destroy()` so
Turbo nav doesn't leak canvas instances.

## Consequences
- Production depends on cdn.jsdelivr.net at request time. Acceptable
  for a personal-app PFM; if dropped, the path is to vendor the +esm
  bundle and hand-resolve the @kurkle/color URL inside it (or switch
  to a UMD-via-`<script>` setup).
- All future charts go through the same controller — config is data,
  not JS. Adding a new chart = `data-controller="chart" data-chart-config-value=…`.
- Chart.js plugins (datalabels, zoom) are extra remote pins when
  needed; defer until a real use case appears.
- If interactive complexity outgrows Chart.js (drill-downs inside the
  canvas, custom tooltips with Turbo Frames), revisit — until then,
  drill-down lives at URL level (separate routes), not chart level.

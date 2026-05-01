import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
import ChartDataLabels from "chartjs-plugin-datalabels"

// Register core controllers/scales/elements/plugins once. Datalabels is
// opt-in per chart via `options.plugins.datalabels` config — registering
// globally is fine because the plugin no-ops when not configured.
Chart.register(...registerables, ChartDataLabels)
// Override the plugin default so unrelated charts don't sprout labels.
Chart.defaults.plugins.datalabels = { display: false }

// Bare lookup — Intl symbols can be locale-dependent ("zł" / "PLN")
// but for axis ticks we want a tight, predictable suffix. Anything not
// here falls back to " <ISO>" (e.g. " GBP") which is ugly but explicit.
const SYMBOL = { PLN: " zł", EUR: " €", USD: " $", GBP: " £" }
const symbolFor = (currency) => SYMBOL[currency] || (" " + currency)

const formatMoney = (value, currency) => {
  const v = Number(value)
  if (!isFinite(v)) return ""
  const sym = symbolFor(currency || "PLN")
  const abs = Math.abs(v)
  if (abs >= 1000) {
    const k = Math.round(abs / 100) / 10
    return (v < 0 ? "-" : "") + k.toString().replace(/\.0$/, "") + "k" + sym
  }
  return Math.round(v) + sym
}

const formatMoneyFull = (value, currency) => {
  const v = Number(value)
  if (!isFinite(v)) return ""
  return new Intl.NumberFormat("pl-PL", { style: "currency", currency: currency || "PLN", maximumFractionDigits: 0 }).format(v)
}

// Walks a config built in the view and replaces declarative string flags
// with real JS callbacks — keeps chart configs in JSON-friendly ERB.
function installFormatters(config) {
  const opts = config.options = config.options || {}
  // Reporting currency baked into the chart by the view — defaults to
  // PLN so old configs without `options.currency` still work.
  const currency = opts.currency || "PLN"

  // Axis tick formatters: scales.{x|y|r}.ticks.tickFormat = "money"
  // (legacy "pln" still accepted for backwards compatibility).
  ;["x", "y", "r"].forEach((axis) => {
    const scale = opts.scales && opts.scales[axis]
    const flag = scale && scale.ticks && scale.ticks.tickFormat
    if (flag === "money" || flag === "pln") {
      scale.ticks.callback = (value) => formatMoney(value, currency)
      delete scale.ticks.tickFormat
    }
  })

  // Datalabels formatter — accepts "pln" / "pln_with_delta" / "delta_pct"
  // string flag at either the global plugin level
  // (options.plugins.datalabels.formatter) or per-dataset
  // (datasets[i].datalabels.formatter).
  // `pln_with_delta` reads delta% from options.metadata[dataIndex] and
  // appends it inline ("1 234 zł  +45%") so the chart shows current +
  // trend without a second bar series fighting for label space.
  // `delta_pct` shows ONLY the delta — for charts where the value is
  // already on the axis (e.g. PLN ticks) and adding it again would
  // duplicate.
  //
  // `color` accepts "delta_sign" / "delta_sign_inverse" string flags.
  // `delta_sign` colors green for positive, red for negative (default
  // "more is good" framing). `delta_sign_inverse` flips it — for spend
  // charts where +% is bad (you spent more) and −% is good. `null` /
  // missing delta keeps the muted-foreground tone.
  const plugins = (opts.plugins = opts.plugins || {})
  const replaceFormatter = (obj) => {
    if (!obj) return
    if (obj.formatter === "money" || obj.formatter === "pln") {
      obj.formatter = (value) => (value > 0 ? formatMoney(value, currency) : "")
    }
    if (obj.formatter === "money_with_delta" || obj.formatter === "pln_with_delta") {
      obj.formatter = (value, ctx) => {
        if (!(value > 0)) return ""
        const base = formatMoney(value, currency)
        const meta = (ctx.chart.options.metadata || [])[ctx.dataIndex]
        if (!meta || meta.delta == null) return base
        const sign = meta.delta > 0 ? "+" : ""
        return base + "  " + sign + meta.delta + "%"
      }
    }
    if (obj.formatter === "delta_pct") {
      obj.formatter = (_value, ctx) => {
        const meta = (ctx.chart.options.metadata || [])[ctx.dataIndex]
        if (!meta || meta.delta == null) return ""
        const sign = meta.delta > 0 ? "+" : ""
        return sign + meta.delta + "%"
      }
    }
    if (obj.color === "delta_sign" || obj.color === "delta_sign_inverse") {
      const inverse = obj.color === "delta_sign_inverse"
      obj.color = (ctx) => {
        const meta = (ctx.chart.options.metadata || [])[ctx.dataIndex]
        if (!meta || meta.delta == null) return "rgba(100, 116, 139, 0.7)"
        const positive = inverse ? meta.delta < 0 : meta.delta > 0
        return positive ? "rgb(22, 163, 74)" : "rgb(220, 38, 38)"
      }
    }
  }
  replaceFormatter(plugins.datalabels)
  if (config.data && Array.isArray(config.data.datasets)) {
    config.data.datasets.forEach((ds) => replaceFormatter(ds.datalabels))
  }


  // Tooltip enrichment via parallel options.metadata array. Each entry
  // matches the dataIndex of the primary dataset; supports share, count,
  // delta, plus a label override. Auto-installs callbacks if metadata
  // is present — view stays JSON.
  if (Array.isArray(opts.metadata)) {
    plugins.tooltip = plugins.tooltip || {}
    const cbs = (plugins.tooltip.callbacks = plugins.tooltip.callbacks || {})

    cbs.label = (ctx) => {
      const v = ctx.parsed.x !== undefined && ctx.chart.options.indexAxis === "y"
        ? ctx.parsed.x
        : ctx.parsed.y !== undefined ? ctx.parsed.y : ctx.parsed
      const ds = ctx.dataset.label ? ctx.dataset.label + ": " : ""
      return ds + formatMoneyFull(v, currency)
    }

    cbs.afterBody = (items) => {
      if (!items.length) return null
      const ctx = items[0]
      // Only enrich the primary (current period) dataset — others share
      // the same metadata, so showing it twice would clutter.
      if (ctx.datasetIndex !== 0) return null
      const meta = opts.metadata[ctx.dataIndex]
      if (!meta) return null
      const lines = []
      if (meta.share != null)  lines.push("Udział: " + meta.share + "%")
      if (meta.count != null)  lines.push("Transakcji: " + meta.count)
      if (meta.delta != null) {
        const sign = meta.delta > 0 ? "+" : ""
        lines.push("Δ vs poprz.: " + sign + meta.delta + "%")
      }
      return lines.length ? lines : null
    }
  }
}

// Mounts a Chart.js chart from a JSON config in `data-chart-config-value`.
// Optional `data-chart-urls-value`: parallel array of href-by-index;
// click → Turbo navigation. Always destroy on disconnect — Turbo nav
// would otherwise leak canvas instances.
export default class extends Controller {
  static values = { config: Object, urls: Array }

  connect() {
    const canvas = this.element.tagName === "CANVAS"
      ? this.element
      : this.element.querySelector("canvas")
    if (!canvas) return

    const config = this.configValue
    installFormatters(config)

    if (this.hasUrlsValue && this.urlsValue.length) {
      const urls = this.urlsValue
      config.options = config.options || {}
      const previousOnClick = config.options.onClick
      config.options.onClick = (event, elements, chart) => {
        if (previousOnClick) previousOnClick(event, elements, chart)
        if (!elements.length) return
        const idx = elements[0].index
        const url = urls[idx]
        if (url) window.Turbo.visit(url)
      }
      canvas.style.cursor = "pointer"
    }

    this.chart = new Chart(canvas, config)
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}

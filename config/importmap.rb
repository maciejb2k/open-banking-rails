# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Chart.js ESM is split into multiple chunks under JSPM/standard ESM,
# which importmap-rails can't follow. jsdelivr's `+esm` returns a single
# pre-bundled module that resolves @kurkle/color via its own absolute
# path (works when served from cdn.jsdelivr.net). Remote pin = no vendor.
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.5.1/+esm", preload: true
pin "chartjs-plugin-datalabels", to: "https://cdn.jsdelivr.net/npm/chartjs-plugin-datalabels@2.2.0/+esm", preload: true

# Architecture Decision Records

Short notes on non-obvious choices. One file per decision.
Format: Title / Context / Alternatives / Decision / Consequences.

| # | Decision |
|---|---|
| [0001](0001-separate-ledger-source-tables.md) | Separate ledger source tables (bank vs manual) |
| [0002](0002-polymorphic-enrichment.md) | Polymorphic enrichment association |
| [0003](0003-postgres-view-for-analytics.md) | Postgres view for analytics reads |
| [0004](0004-encryption-at-rest.md) | Selective ActiveRecord encryption |
| [0005](0005-llm-confidence-gating.md) | LLM enrichment with confidence gating |
| [0006](0006-cash-tracking-opt-in.md) | Cash tracking is opt-in |
| [0007](0007-chart-library.md) | Chart library: Chart.js via importmap |
| [0008](0008-ai-insight-architecture.md) | AI insight: facts-only narration |
| [0009](0009-operation-run-tracker.md) | `OperationRun` as the generic long-op tracker |
| [0010](0010-three-layer-category-model.md) | Three-layer category model (ltree + kind + facets) |
| [0011](0011-first-run-setup.md) | Single-user-shaped multi-tenant + first-run UI |
| [0012](0012-per-user-llm-credentials.md) | Per-user LLM credentials + provider registry |
| [0013](0013-enable-banking-adapter-shape.md) | Enable Banking adapter shape (Client/Api/Operations/Result) |
| [0014](0014-self-hosted-deployment.md) | Self-hosted deployment shape (compose + ENV-only + bootstrap) |

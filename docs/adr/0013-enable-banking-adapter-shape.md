# 0013 - Enable Banking adapter shape (Client / Api / Operations / Result)

## Context
PSD2 access via Enable Banking spans ~10 endpoints, needs per-request
JWT signed with the TPP private key, and returns inconsistent error
shapes across banks. The provider is replaceable in principle
(GoCardless dropped its free tier; the next one might too), and the
README promises "swapping … is a small change" - only true with clean
seams.

## Alternatives
- **One fat client class with one method per endpoint** - business
  logic (compose multiple calls + persist) leaks into the client or
  controllers.
- **Gem-style facade** (`EnableBanking.session(...).accounts...`) -
  ergonomic, but mocking layered chains in tests is painful.
- **Layered adapter: transport / per-endpoint Api / domain Operations /
  uniform Result.**

## Decision
Four layers:
- **`Client`** - Faraday + JWT. Returns `Result` for every call;
  **never raises on HTTP errors** (network failure → `Result(status: 0)`).
  Crypto/config errors propagate as `EnableBanking::ConfigError`.
- **`Api::*`** - one class per endpoint. Pure request shape, no
  persistence, no domain logic.
- **`Operations::*`** - combine API calls + persistence + state changes.
  Subclass `Operations::Base` which converts `EnableBanking::Error` to
  a per-operation `Failed`. This is the layer controllers and jobs talk to.
- **`Result`** - uniform value across all transport responses.

## Consequences
- Swapping the provider = re-implement `Client` + `Api/*` + adjust
  `Operations/*` calls. The operation API, `Result` shape, and the
  job/controller layers stay put.
- Per-account error in a sync doesn't kill the run - caught at the
  per-account boundary, reported via `on_account_synced` into
  `OperationRun#summary`.
- `Client` returning `Result` (not raising) means call sites handle
  routine bank-side errors with `if result.success?`, not rescue blocks.
- Revisit if: a second provider ships and the response shapes diverge
  enough that `Result` hides meaningful differences - at that point
  introduce a `Banking::Provider::*` abstraction one level up.

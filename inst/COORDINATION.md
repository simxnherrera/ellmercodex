# Implementation coordination

The original coding prompt requested by the continuation brief was not present
in the repository or supplied attachment. `docs/feasibility.md`,
`docs/technical-design.md`, `poc/README.md`, and all files under `poc/` are the
authoritative baseline for this phase.

## Public API

The package exports exactly these six functions:

* `codex_login()`
* `codex_logout()`
* `codex_account()`
* `codex_models()`
* `codex_available()`
* `chat_codex()`

All transport, parsing, diagnostics, compatibility, refresh, configuration,
credential, and helper functions remain internal. `codex_diagnostics()` may be
implemented only as an internal helper because it is not in the fixed API.

## Dependency policy

Use imported packages only for required runtime behavior: `ellmer`, `httr2`,
`httpuv`, `jsonlite`, `keyring`, `openssl`, `rlang`, and `coro`. Prefer
namespace-qualified calls. Put testing, documentation, and optional fallback
support in `Suggests`; no package load, test, or example may authenticate, open
a browser, read credentials, or access the network. Do not use unexported
upstream APIs unless no exported alternative exists; any unavoidable use must
be isolated, version-gated, and documented.

## File ownership

* Luna agent `metadata_ellmer`: `DESCRIPTION`, `LICENSE`, `NEWS.md`,
  `NAMESPACE`, `R/ellmercodex-package.R`, `R/provider-codex.R`,
  `R/chat-codex.R`, `tests/testthat/test-ellmer.R`, and package-layout-only
  metadata.
* Luna agent `auth_models`: `R/auth.R`, `R/oauth.R`, `R/credentials.R`,
  `R/conditions-auth.R`, `R/models.R`, `R/diagnostics.R`,
  `tests/testthat/test-auth.R`, `tests/testthat/test-credentials.R`,
  `tests/testthat/test-models.R`, and `tests/testthat/test-diagnostics.R`.
* Luna agent `transport_cran_research`: `R/config.R`, `R/transport.R`,
  `R/stream.R`, `tests/testthat/test-transport.R`,
  `tests/testthat/test-stream.R`, `tests/testthat.R`, test helpers and fixtures,
  `.github/workflows/R-CMD-check.yaml`, and `docs/research-risk-review.md`.
* Lead: `README.md`, final roxygen reconciliation, integration fixes, remaining
  tests/documentation, and verification artifacts.

Agents must not edit files outside their ownership. The lead reconciles all
cross-file calls, generated documentation, namespace entries, and package-check
failures after parallel work completes.

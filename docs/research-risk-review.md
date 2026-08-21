# Transport and release-risk review

Checked 2026-08-20. This note records the boundary between what is documented
by a primary source and what this repository has only observed in open-source
clients or in the proof of concept. It informs the package's compatibility
policy; it is not itself a prohibition on an experimental CRAN release.

## Executive finding

The pure-R implementation is technically testable offline: it constructs the
observed Responses request, parses buffered SSE fixtures, classifies failures,
and assembles text even when the terminal event has no `output` items. The
implementation should remain experimental. The direct subscription OAuth and
`chatgpt.com/backend-api/codex/responses` route are not established as a
supported public API for an independent R package. The project deliberately
accepts that upstream-compatibility risk in order to provide a pure-R user
experience similar to other independent coding clients. Absence of a documented
contract is not described here as either permission or prohibition.

The documented integration surface is Codex app-server. OpenAI describes
app-server as the interface for rich clients and says it provides
authentication, conversation history, approvals, and streamed agent events;
the implementation is open source in the Codex repository. It is a
JSON-RPC-oriented Codex harness, not the raw HTTP/SSE endpoint implemented in
this package. App-server is therefore useful context, but migration to it is not
the selected package direction. [OpenAI Codex App Server documentation](https://developers.openai.com/codex/app-server)

## Evidence matrix

| Area | Documented primary-source fact | Observed or unresolved risk | Current package decision |
| --- | --- | --- | --- |
| App-server support | The official App Server page recommends app-server for deep product integrations, including authentication, history, approvals, and streamed agent events. It points to the open-source implementation. | A small R package would need a local app-server binary/process and a JSON-RPC client; this repository currently implements direct HTTP instead. | Keep the direct route. Document it as experimental and isolate every compatibility-sensitive value so upstream changes are repairable. |
| Authentication | App-server documents API-key login, Codex-managed ChatGPT browser login (`chatgpt`), device-code login (`chatgptDeviceCode`), and an experimental externally managed `chatgptAuthTokens` mode. In managed mode Codex persists and refreshes tokens; in external-token mode the host owns refresh. [Auth section](https://developers.openai.com/codex/app-server) | The raw authorization URL, token URL, client identifier, account claim, scope, fixed callback port, and direct subscription bearer flow used by this package are observed implementation details. The reviewed docs do not grant arbitrary third-party native clients a registration or reuse right. | No live OAuth, browser, keyring, or credential-file access in package checks. Never read another client's token files or impersonate another originator. |
| Callback / localhost | App-server's browser example uses a localhost callback hosted by app-server, with a dynamically selected port in its documented `authUrl`; the app-server owns the lifecycle. [Browser flow](https://developers.openai.com/codex/app-server) | The PoC's `http://localhost:1455/auth/callback` redirect and `127.0.0.1` bind were copied from observed Codex/Pi behavior. The exact spelling and fixed port are not a public contract, and a port collision or local policy can prevent login. | Keep callback code explicit and loopback-only. It is invoked only by an explicit user action, and it is not exercised by examples, tests, or CI. |
| Direct HTTP endpoint | OpenAI API model pages document models being available through the Responses API and official SDKs, including streaming support for listed API models. [Models](https://developers.openai.com/api/docs/models/text) | `https://chatgpt.com/backend-api/codex/responses`, `OpenAI-Beta: responses=experimental`, `ChatGPT-Account-Id`, and the subscription bearer semantics are not documented here as a general public API. HTTP status and SSE event details may change without compatibility guarantees. | Centralize endpoints/headers, send `stream: true`, buffer only in the transport boundary, and classify protocol changes. No automatic retries, which could duplicate an accepted generation. |
| Model discovery | App-server documents `model/list`, including visible/hidden model entries, reasoning options, input modalities, and the default model marker. [App-server model/list](https://developers.openai.com/codex/app-server) | A direct subscription HTTP model catalog is not documented. API model pages and app-server catalogs are not interchangeable, and account/workspace eligibility can differ. A static package default can become unavailable. | Query the observed account-specific `/codex/models` endpoint only after explicit authentication. Do not copy another client's private model list; expose the returned effort metadata and let the server remain authoritative. |
| ellmer seam | The official ellmer source exposes `chat_openai()` as a Responses API factory with `base_url`, dynamic `credentials`, `api_headers`, and `service_tier`; its OpenAI stream parser consumes output-text deltas and terminal response events. [ellmer OpenAI provider](https://github.com/tidyverse/ellmer/blob/main/R/provider-openai.R) | The observed subscription terminal event can omit output that was present in deltas. ellmer 0.4.2 also does not assemble fragmented Responses function-call argument events. A native provider would require unstable/unexported upstream seams. | Keep the instance fallback narrow and version-gated. Structured output and registered function tools use separately checked compatibility seams; async calls and a native provider remain outside the interface. |
| OS keyring | The CRAN `keyring` package provides a platform-independent API over macOS Keychain, Windows Credential Store, Linux Secret Service, and fallback backends. [keyring documentation](https://keyring.r-lib.org/reference/keyring-package.html) | Backend availability, locked stores, interactive prompts, and CI environment behavior vary. A check process must not read, overwrite, or delete a maintainer's real keyring entry. | The default path uses only the package's own service/username. Tests use fixture credentials in memory; live persistence/refresh is manual acceptance evidence, never an automatic test. |
| CRAN / network | CRAN requires packages using internet resources to fail gracefully, keeps external resources to a minimum, requires public APIs, and disallows insecure TLS workarounds. [CRAN Repository Policy](https://stat.ethz.ch/CRAN/web/packages/policies.html) | Network availability, rate limits, OAuth eligibility, account plans, and model rollout are outside a deterministic package check. A browser or token prompt can hang or mutate user state. | All tests use local mocked values and fixture files. There are no live requests, no automatic auth, no browser launch, no credential reads, and no network retry path. |
| Examples / checks | Writing R Extensions says to avoid internet access during installation, requires executable examples to avoid facilities such as internet access, and notes that `R CMD check` runs package tests and examples. [Writing R Extensions](https://cran.r-project.org/doc/manuals/r-release/R-exts.html) | An example that silently calls login, keyring, localhost, or the backend would be nondeterministic and unsuitable for CRAN. | Examples and checks must only demonstrate validation/configuration or use `\dontrun{}` for an explicitly user-run live flow, with no credentials embedded. CI runs offline tests only. |

## Protocol boundary used by this implementation

The transport has three deliberately separate stages:

1. `config.R` owns every unstable endpoint, header, callback value, client
   identifier, originator, user agent, and model default.
2. `transport.R` validates input, creates a minimal Responses body with
   `stream: true` and `store: false`, performs one HTTP request, and maps
   status failures to package conditions without copying raw bodies into an
   error.
3. `stream.R` applies SSE framing rules, tolerates unknown event types,
   assembles output-text deltas, supports a terminal-response fallback, and
   raises explicit conditions for failed, incomplete, malformed, or
   terminal-less streams.

This separation is intentional. It allows offline protocol fixtures to test
the parser without invoking OAuth or `httr2::req_perform()`, and it leaves a
single replacement seam if the observed direct protocol changes or a different
documented direct endpoint becomes available.

## CRAN-safe test and CI requirements

The following are release requirements, not optional conveniences:

- No test, helper, example, package load hook, or CI test step may open a
  browser, start OAuth, read credentials, write to a user keyring, or make an
  authenticated request.
- Localhost fixtures must be pure in-memory or file fixtures. If a future
  integration test needs a loopback listener, it must bind a test-only port,
  close it in an unconditional cleanup handler, and remain opt-in outside
  `R CMD check`; the current suite does not start one.
- Tests must assert protocol shape, redaction, status classification, framing,
  unknown-event tolerance, terminal handling, and incomplete/error conditions.
  They must not assert a live model's wording, current catalog, plan limits, or
  timing.
- Keyring integration, refresh rotation, and browser callback tests belong in
  a manual acceptance script or an explicitly opt-in local test profile. They
  must use a package-owned service namespace and must never delete a broad or
  default keyring.
- No retry helper should be introduced in the direct generation path without
  an idempotency design and a test proving that an accepted streamed request
  cannot be duplicated.
- CI metadata under `.github/` should be excluded from the CRAN source tarball
  through `.Rbuildignore`; otherwise `R CMD check` reports the hidden directory
  as a package NOTE even though the workflow is useful in the repository.

The checked-in fixtures under `tests/testthat/fixtures/` satisfy these rules:
they contain no tokens, email addresses, account IDs, authorization codes, or
external URLs that are contacted.

## Release posture and remaining risks

The project has chosen to publish the direct integration as an experimental
package. An official registration or support statement is therefore not a CRAN
release gate, but the package must remain candid about the absence of that
contract and must fail safely when compatibility changes.

Do not describe the package as production-ready until all of the following are
true:

1. OpenAI documents or confirms a supported third-party integration and
   registration story for the chosen authentication and generation path, or
   a replacement documented direct surface is adopted.
2. The supported surface defines model discovery/eligibility and streaming
   semantics without relying on another client's private catalog or headers.
3. ellmer exposes a stable, exported integration/finalization seam or the
   package pins and tests a clearly supported version range with an approved
   extension strategy. The current structured-output fallback is explicitly
   covered by the ellmer 0.4.x gate and compatibility tests.
4. Cross-platform keyring behavior, refresh-token rotation, logout scope, and
   failure recovery are tested without touching real user credentials in CI.
5. CRAN checks remain offline and deterministic, examples never require
   internet or write permission, and all external-resource failures are
   graceful and actionable.
6. Security and privacy review covers token redaction, callback state/PKCE,
   loopback binding, TLS verification, account routing, logging, and the
   consequences of a malicious or compromised local process.

Until then, releases remain experimental. They do not claim OpenAI support,
policy approval, or production readiness.

# Implementation vs. Ground Truths

Initial audit date: 2026-08-21. The requirements baseline is
`docs/project-ground-truths.md`; it is treated as a specification, not as
evidence that a requirement is implemented. The released comparison point is
tag `v0.1.5` at commit `7c5436f` (also current `HEAD`). The initial audit was
written before the follow-up fixes below and is retained through the resolved
finding notes for auditability.

Follow-up verification date: 2026-08-21. The source-loading offline runner
passed 70 tests and 337 expectations with no warnings. The explicitly
authorized opt-in live runner also passed; it wrote only redacted artifacts
outside the repository. None of these working-tree changes are part of
`v0.1.5` until a later authorized commit and release. The working tree now
targets package version `0.1.6`.

## Executive verdict

The follow-up implementation resolves the audited model-selection,
unknown-metadata, parallel/batch-contract, duplicate-tool-architecture, and
live-evidence gaps. `chat_codex(model = NULL)` now selects from the
authenticated account catalog and fails actionably when discovery cannot
support a safe choice. Missing usage fields remain unknown, every documented
parallel/batch helper was exercised offline, and
`R/ellmer-compatibility.R` is the sole tool architecture.

The bounded stable-core Chat contract now has both deterministic offline
coverage and a passing authorized live acceptance run. The remaining material
risk is unchanged: OAuth identifiers, endpoints, headers, and protocol
assumptions are observed and undocumented, with no claim of independent
registration, approval, or official OpenAI support. That is an upstream
transport/product decision, not a reason to hide the limitation or introduce a
Codex CLI dependency.

## Ground-truth matrix

| Ground-truth area | Status | Evidence and gap |
|---|---|---|
| Product identity: an independent `ellmer` companion, not a CLI/agent wrapper | **Implemented** | `README.md:3-15` and `R/chat-codex.R:526-680` present the package as a normal `ellmer` Chat; no runtime process invocation is present in the package source. |
| Runtime architecture: pure R auth, refresh, models, HTTPS, SSE, and Chat | **Implemented** | `DESCRIPTION:9-19` has the R/HTTP dependencies and no CLI dependency; `R/auth.R`, `R/models.R`, `R/stream.R`, and `R/ellmer-compatibility.R` contain the corresponding paths. The direct endpoint and native-client assumptions remain a security/protocol risk (see below). |
| Auth/account: explicit browser OAuth, safe storage, refresh rotation, injected-credential continuity, no foreign auth-file scraping or secret exposure | **Partial** | `R/auth.R:56-120,165-240,442-535` implements the explicit OAuth boundary and redacted account output. `R/credentials.R` delegates encrypted token caching and refresh rotation to httr2, while `R/ellmer-compatibility.R:141-187` keeps injected credentials process-local without re-entering the persistent cache. However, `R/config.R:8-30` uses an observed native client ID and direct undocumented endpoints; the repository has no independent registration evidence. |
| Public API: exactly six public helpers and a normal usable Chat | **Implemented** | `NAMESPACE:3-11` exports exactly `codex_login`, `codex_logout`, `codex_account`, `codex_models`, `codex_available`, and `chat_codex` (apart from S3 print methods). `R/chat-codex.R:604-680` constructs the Chat and maps `effort` to reasoning parameters. |
| Full `ellmer` compatibility: ordinary/multiturn, sync/async, structured, tools, rich content, cancellation, clone/history, callbacks, errors, and metadata | **Implemented for the supported ellmer range** | The private seam and loops are implemented in `R/ellmer-compatibility.R`; ordered stream/rich conversion, unknown usage preservation, tools, async paths, clone/history, cancellation, and error recovery have deterministic fixtures. The live runner also passed ordinary/multiturn output, streaming, structured output, tools, async, rich input, cancellation, cloning, and history. Parallel/batch helpers remain the documented stable-core exception. |
| Models/reasoning: account-specific catalog, appropriate dynamic `model = NULL`, explicit fallback, selectable compatible effort | **Implemented with documented transport risk** | `R/models.R` selects the lowest-priority usable row from the authenticated catalog, honors `ELLMERCODEX_MODEL` only as an explicit override, and turns empty/unavailable discovery into `codex_model_selection_error`. `chat_codex()` validates `effort` and `params$reasoning_effort` against the selected row. Offline fixtures cover selection/errors; the live catalog was non-empty and the runner passed both default and explicit selection plus a supported effort. |
| Quality/release: offline coverage, opt-in live validation, CRAN-safe docs/examples, and release hygiene | **Verified for this working tree; not released** | The source-loading runner passed 70 tests and 337 expectations with no warnings; roxygen documentation was regenerated; the live runner passed with redacted artifacts outside the repository. R CMD build and check for `0.1.6` completed with no errors or warnings; the two remaining notes are the expected new-submission note and local HTML Tidy age note. The final diff was reviewed and no generated build artifacts remain. Release authorization remains a separate gate. |
| Non-goals: no coding-agent filesystem/shell/background/multi-agent runtime | **Implemented** | The public and transport code is a direct-R chat client with no CLI, app-server, local proxy, agent loop, shell, filesystem, background worker, or multi-agent runtime. The obsolete manual tool parser and its fixtures were removed. |
| Decision rules: preserve direct Chat semantics, make limitations visible, and avoid silent degradation | **Implemented with the parallel/batch exception** | The stream-only boundary is explicit; actual parallel and batch entry points were tested offline; docs now distinguish the package blocker for parallel helpers from ellmer's generic unsupported-provider error for batch helpers. Missing token values remain `NA`/unknown, and default model discovery no longer silently falls back to a hardcoded model. |

## Released baseline versus current work

- `v0.1.5` is the tagged release at `7c5436f`. It contains the direct-R
  architecture, six exports, OAuth/httr2-cache paths, the `ellmer` compatibility
  seam, SSE/tool/rich/async code, and the bounded parallel/batch contract.
- The current uncommitted changes extend the earlier model/catalog work with
  dynamic default selection, reasoning validation, unknown usage handling,
  actual parallel/batch contract tests, the single authoritative tool path,
  generated documentation, and the expanded live runner. They are not part of
  the tag and must not be described as released behavior until committed and
  published.
- `docs/project-ground-truths.md` is itself untracked and is the audit input;
  it is not release evidence.

## What is already solid

- The public surface is deliberately small and matches the stated six-helper
  contract.
- Loading the package, checking availability, and constructing the documented
  auth paths are designed without credential-store or network side effects.
- PKCE/state validation, callback handling, redaction, httr2 encrypted cache
  integration, and refresh rotation have explicit code and offline fixtures.
- The adapter preserves the ordinary `ellmer` lifecycle rather than exposing a
  reduced custom chat object. Stream accumulation handles ordered text,
  reasoning, tool/function-call deltas, terminal events, structured output,
  images/PDFs, cancellation, history, cloning, and async tool loops.
- The account-specific model catalog is queried at construction when needed;
  no runtime Codex executable is consulted. Effort values are checked against
  the selected row's advertised capabilities.
- The provider leaves omitted token counts as unknown and records supplied
  usage without fabricating zeros. A missing price remains an unknown cost.
- The unsupported parallel/batch boundary is intentional and documented as a
  product limitation; it is preferable to pretending that a stream-only
  provider can satisfy those calls.

## Drift, silent degradation, and overbroad claims

1. **Default-model drift — resolved.** `R/config.R` now treats
   `ELLMERCODEX_MODEL` as an explicit override, while `R/models.R` queries the
   account catalog, chooses a usable row deterministically, and raises an
   actionable condition for empty/unavailable discovery. Offline and live
   acceptance both cover the behavior.
2. **Client identity/protocol drift.** `R/config.R:8-30` uses an observed native
   client ID and direct `auth.openai.com`/`chatgpt.com/backend-api` routes. The
   honest `originator = "ellmercodex"` header is good disclosure, but it does
   not establish that this package is an approved independently registered
   client. This is the largest unresolved security and service-compatibility
   question.
3. **Silent metadata degradation — resolved.** `R/ellmer-compatibility.R`
   preserves omitted usage fields as `NA`/unknown and bypasses ellmer's 0.4.2
   zero-filling logger only when necessary. The missing-usage SSE fixture and
   turn-level assertions are in `tests/testthat/test-ellmer-interface.R`.
4. **Batch limitation claim — resolved.** The actual parallel, text,
   structured, batch, and completed helper entry points are exercised offline.
   Documentation now promises only the package blocker for parallel helpers;
   batch helpers are documented with ellmer's generic unsupported-provider
   condition and no state file.
5. **Two tool architectures — resolved.** The obsolete `R/tool-calling.R`
   parser/loop and its JSON fixtures were removed. Sync and async tools,
   multiple rounds, callbacks, failures, cancellation, ordered rich content,
   dangling-tool recovery, and history remain covered by the authoritative
   `R/ellmer-compatibility.R` path and its tests.
6. **Evidence language — resolved for this tree.** The source-loading runner
   passed the full offline suite and the authorized live runner passed explicit
   login, catalog/default/explicit model selection, supported reasoning,
   exactly-once ordinary/multiturn output, streaming, structured output, tools,
   async, rich input, cancellation, cloning, and history. Live artifacts were
   redacted and kept outside the repository. The live run observed eight catalog
   rows and a supported `low` effort; offline fixtures additionally cover empty
   discovery and omitted usage, which were not exercised by that account.

## Release blockers and next actions

### P0 — remaining upstream/product decision

1. Decide whether the project will continue using the observed native OAuth
   client identifier and undocumented direct subscription endpoints. The code
   centralizes these assumptions in `R/config.R`, identifies the originator
   honestly, documents the risk, and makes no independent-registration or
   official-support claim. A documented upstream route or a product decision to
   accept this experimental boundary is still required for long-term support.

### P1 — local release gates

2. R CMD build/check and final diff review are complete for `0.1.6`. Keep live
   validation opt-in and keep credentials, personal identifiers, and live
   artifacts out of the repository.

### P2 — release hygiene

3. Do not commit, push, tag, or publish until the owner separately authorizes
   release work. Keep the experimental/undocumented transport disclosure
   prominent until the client-registration and protocol-support question is
   resolved.

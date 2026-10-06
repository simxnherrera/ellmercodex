# ellmercodex 0.1.64

## Breaking changes: documented "Sign in with ChatGPT" flow

* Authentication now follows OpenAI's documented "Sign in with ChatGPT" flow
  for open-source, locally hosted apps
  (<https://developers.openai.com/siwc/token-sharing-open-source>). The
  package no longer reuses the Codex CLI OAuth client or calls the
  undocumented `chatgpt.com/backend-api/codex` endpoints. **Existing
  credentials cannot be migrated: run `codex_login()` again.**
* `codex_login()` registers dynamically with `client_id=dynamic_agent_client`,
  stores the client ID that OpenAI issues for the chosen account and
  workspace, and reauthorizes that registration on later sign-ins. It sends a
  stable `ext_agent_host_id`, created once per host, and uses PKCE and a nonce.
  The ID token is verified against OpenAI's published keys, and sign-in fails
  with the new `codex_plan_scope_error` when ChatGPT plan usage
  (`chatgpt.tokens.use.direct`) is not granted. The package now imports
  `jose` for ID token verification.
* The OAuth callback moved from `http://localhost:1455/auth/callback` to
  `http://127.0.0.1:1455/callback`, as the documentation requires. Set
  `ELLMERCODEX_CALLBACK_PORT` to use another port.
* Credentials moved from httr2's OAuth cache to a package-owned
  `credentials.json` (mode `0600`, atomic writes) in
  `tools::R_user_dir("ellmercodex", "config")`, overridable with
  `ELLMERCODEX_HOME`. `HTTR2_OAUTH_CACHE` no longer applies. Refreshes are
  serialized across R processes because refresh tokens rotate.
* `codex_logout()` gains `revoke = TRUE` and now revokes the refresh token
  with OpenAI before deleting the local credential. It also removes the old
  httr2 cache entry. To switch account or workspace, log out and sign in
  again.
* Chats and `codex_models()` use the public `https://api.openai.com/v1`
  Responses and Models endpoints with only the bearer token; the
  `ChatGPT-Account-Id`, `OpenAI-Beta`, and `originator` headers are gone.
  `codex_models()` keeps models with `visibility: "list"`, and its
  `client_version` argument is deprecated and ignored
  (`ELLMERCODEX_CLIENT_VERSION` is no longer read).
* Requests follow the ChatGPT plan usage preview limits: system prompts are
  sent as `developer` messages, function tools are grouped in an `ellmer`
  namespace, and `temperature`, `top_p`, `max_tokens`, `metadata`,
  `previous_response_id`, and the other excluded Responses arguments now fail
  with `codex_chat_argument_error` before a request is sent.
* A `response.incomplete` event now fails a Chat turn with
  `codex_incomplete_error` instead of returning a truncated turn.
* Documented plan error codes map to new subclasses that keep the existing
  parents: `codex_usage_limit_error` (a `codex_rate_limit_error`),
  `codex_usage_unavailable_error` (a `codex_server_error`),
  `codex_plan_ineligible_error` (a `codex_authentication_error`), and
  `codex_unsupported_capability_error` (a `codex_malformed_request_error`).
  Synchronous chats now raise these package conditions, rather than httr2
  errors, for HTTP failures before the stream opens.

## Other changes

* Codex generation requests no longer inherit ellmer's automatic retries, as
  documented in the technical design: a retried request could duplicate a
  generation the service already accepted.
* Codex requests and turn costs are now built without five unexported ellmer
  helpers, reducing the private ellmer surface ahead of a CRAN submission.

* `chat_codex()` now accepts explicitly selected models omitted from the
  account catalog. The service validates those model IDs and reasoning efforts.

# ellmercodex 0.1.63

* `chat_codex()` now supports ellmer 0.5.0 and later through a Model/Provider
  adapter, request callbacks, and checked private Chat contracts. Provider
  token counting and file management report unsupported operations before a
  request; offline CI tests the minimum and latest ellmer releases (#3).
* Documented a single-process Linux VM deployment that retains httr2 OAuth
  credentials across restarts and redeploys, with offline lifecycle coverage
  and an httr2 1.3.0 minimum for the cache path and pruning behavior (#2).

# ellmercodex 0.1.62

* Removed obsolete private OAuth callback/PKCE and legacy ellmer structured
  stream-repair helpers now superseded by the httr2 and ellmer compatibility
  paths. Updated tests and internal documentation; no public API behavior
  changes.

# ellmercodex 0.1.61

* Replaced the OS-keyring credential backend with httr2's encrypted OAuth
  cache. Cached tokens are stored in a user-level `ellmercodex` cache and
  refreshed without macOS Keychain prompts.

* Fixed streamed reasoning summaries whose initial `summary` array is empty.
  Reasoning deltas now initialize the first summary part and use the streamed
  reasoning item identifier when it is available.

* Selects the default model from the authenticated account catalog, validates
  reasoning effort against advertised model capabilities, and reports
  actionable discovery failures instead of silently using a static model.
* Preserves omitted usage values as unknown, tests the actual ellmer
  parallel/batch boundaries, and consolidates tool execution in the
  version-gated compatibility architecture.
* Expands the opt-in live acceptance runner and documents the remaining
  observed, undocumented transport risk without introducing a Codex CLI
  runtime dependency.

# ellmercodex 0.1.5

* Fixed Codex Responses streaming history duplication by correlating streamed
  text deltas with their provider `item_id` and merging completed message
  items instead of recording the same assistant text twice.
* Preserved terminal-only message output and removed duplicate message content
  from rich content streaming.
* Added regression coverage for live-shaped Responses event sequences and a
  full maintainer runner covering offline tests, live chat/streaming,
  structured and async methods, tools, cancellation, multimodal input, model
  discovery, and redacted persisted artifacts.

# ellmercodex 0.1.4

* Expanded the public reference pages and getting-started vignette with the
  authentication workflow, credential side effects, model-catalog columns,
  condition handling, compatibility boundaries, and offline-check semantics.
* Defined the stable contract as the complete public ellmer 0.4.2 `Chat`
  object for interactive, single-conversation operations. The separately
  exported parallel and batch helpers remain explicitly unsupported because
  the subscription transport is stream-only; the package no longer presents
  that limitation as a blocker to the bounded core contract.
* Corrected offline streaming fixtures and compatibility assertions so the
  release gate tests the actual ellmer 0.4.2 return and history semantics.

# ellmercodex 0.1.3

* Reworked the ellmer integration around a version-gated `CodexProvider` and
  ellmer 0.4.2's own `Chat` lifecycle. The public Chat methods, R6 cloning,
  sync/async tool loops, structured output, rich ordered content, cancellation,
  history, echo, usage, cost, duration, and finish metadata now share one
  compatibility seam rather than per-instance public-method patches.
* Added clone-safe credential references with refresh-token rotation and
  persistent updates across all Chat request paths. Non-streaming ellmer
  parallel/batch helpers now fail explicitly because the Codex subscription
  endpoint is stream-only; these helpers are outside the bounded Chat
  compatibility contract.
* Documented the complete installed ellmer 0.4.2 Chat interface and capability
  matrix in `docs/ellmer-chat-interface.md`.

# ellmercodex 0.1.2

* Added authenticated Codex model discovery with per-model reasoning-effort
  metadata; the package no longer invents a static model catalog.
* Added `effort`, ellmer `params()`, and `api_args` support to `chat_codex()`.
  Reasoning effort is forwarded using ellmer's Responses-compatible mapping.
* Added streamed structured output through `Chat$chat_structured()`, including
  repair of the terminal assistant turn into ellmer `ContentJson`.
* Added first-class ellmer function-tool calling through `chat_codex()`,
  including fragmented Responses arguments, multiple/sequential calls,
  local tool errors/rejections, streaming content, and tool-preserving
  conversation history. Structured-output requests intentionally continue to
  disable registered tools, matching ellmer.
* Added asynchronous ellmer chat, structured-output, and content-streaming
  methods, including sequential/concurrent tool modes, tool callbacks,
  cancellation controllers, and terminal assistant-turn repair.
* Preserved ellmer image/PDF input serialization and terminal image content
  while repairing streamed assistant text.
* Added offline fixtures for model discovery, effort propagation, and
  structured-output conversion; updated the experimental compatibility notes.

# ellmercodex 0.1.0

* Converted the validated proof of concept into an installable R package with
  six exported functions, offline examples, a getting-started vignette, and a
  manual opt-in compatibility check.
* Added the explicitly opt-in `chat_codex()` wrapper around ellmer's Chat
  seam. The compatibility layer was tested against ellmer 0.4.2, buffers
  streamed text, and repairs the terminal assistant turn used for multi-turn
  history.
* Added package-scoped OS-keyring persistence, an explicitly enabled encrypted
  file fallback, refresh-token rotation, logout, and redacted diagnostics.
* Added fixture-based request, SSE, credential, authentication, diagnostic,
  package-contract, and ellmer compatibility tests that do not use the network
  or inspect user credentials.
* Documented that the observed subscription OAuth and direct Responses
  transport are experimental, undocumented compatibility behavior. This
  package is not affiliated with or endorsed by OpenAI.

# `ellmercodex` technical design

## Scope

This design covers the bounded stable core: `chat_codex()`, explicit browser
login, secure persistence and refresh, SSE Responses calls, offline
availability diagnostics, account-specific model discovery, reasoning effort,
and the complete public `ellmer` 0.4.2 Chat interface for interactive,
single-conversation operations. The package uses a version-gated provider
subclass plus one private Chat execution seam because the Codex endpoint is
stream-only; it does not replace public Chat methods. The separately exported
ellmer parallel/batch helpers are outside this core contract.

Live testing resolved a key assumption: the subscription backend returns HTTP
400 for `stream: false` and requires streaming. The authorized next phase added
the smallest buffered SSE parser, after which persistence, forced refresh, and a
genuine-process restart all passed.

## Components

```text
explicit codex_login()
        |
        v
auth.R: PKCE + state -> browser -> 127.0.0.1 callback -> token exchange
        |
        +-------------------------+
        |                         |
        v                         v
credentials.R: httr2 OAuth cache  auth object in memory
        |                         |
        +------------+------------+
                     v
transport.R: refresh if due -> stream=true request -> SSE events -> text
                     |
                     v
               codex_generate()

chat_codex() -> ellmer::Chat$new(CodexProvider)
             -> ellmer public Chat lifecycle
             -> private chat/submit compatibility seam
             -> stream-only Codex request -> ordered response conversion

chat$stream_async() -> ellmer async stream -> TurnAccumulator -> Chat history
chat$chat_async() -> ellmer async tool loop -> promise return shape
chat$chat_structured_async() -> typed async stream -> ContentJson conversion

registered tools -> ellmer ToolDef execution/callback loop
                 -> ContentToolResult input -> next Responses round

codex_models() -> authenticated Codex model catalog + effort metadata
chat$chat_structured() -> streamed JSON -> repaired ellmer ContentJson turn
codex_available() -> offline dependency/configuration checks by default
```

`R/config.R` is the only location containing unstable endpoints, the observed
client identifier, protocol header, callback URI, model override, originator,
and shared transport-header construction. Every value is marked as observed
rather than a documented public contract. The package has no independent client
registration or approval claim.

## Authentication lifecycle

1. Loading the package defines functions only. It has no authentication,
   browser, credential, or network side effects.
2. An explicit `codex_login()` creates 64 random bytes for a PKCE verifier and 32
   random bytes for OAuth state using `openssl::rand_bytes()`.
3. The verifier is base64url encoded; its challenge is the base64url-encoded
   SHA-256 digest.
4. A callback server binds only to `127.0.0.1:1455`. The registered redirect
   remains exactly `http://localhost:1455/auth/callback`, matching Pi's
   compatibility-sensitive behavior.
5. Only after the server is listening does the function open the authorization
   URL. The callback must have the expected path, a code, and an exact state
   match.
6. The code is exchanged with a form-encoded request. The callback server is
   stopped through `on.exit()` after success, failure, interruption, or timeout.
7. The account identifier is read from the namespaced JWT claim. JWT payloads
   are decoded only to obtain routing metadata and expiry; this is not signature
   validation and must not be treated as authorization. The server-issued token
   remains the authority.
8. Expiry uses the access-token `exp` claim when available, otherwise
   `expires_in`, with a 60-second refresh margin.
9. Refresh is handled by httr2 for package-managed credentials. A rotated
   refresh token is retained in httr2's encrypted cache before the next request.

The implementation never reads Codex CLI or Pi files, never accepts a supplied
foreign session, and never prints authorization codes, state, verifier, tokens,
or account identifiers.

## Credential storage

The package delegates persistence to httr2's encrypted OAuth cache. The client
is named `ellmercodex`, so httr2 stores its token below
`tools::R_user_dir("httr2", "cache")/ellmercodex`. The cache location can be
overridden with `HTTR2_OAUTH_CACHE`; `persist = FALSE` keeps the token in
httr2's process-local cache only. No OS keyring is used.

`codex_logout()` deletes only the named httr2 cache and process-local token.
`codex_account()` reports
authentication and expiry while replacing the account identifier with a
literal redaction.

The acceptance sequence calls `codex_login(persist = FALSE)` to prove the
process-local path. A genuinely new R process can then load the encrypted httr2
cache, refresh a managed token, and persist any rotated refresh token without a
Keychain prompt.

## Transport boundary

- `codex_request_headers()` creates bearer, account-routing, honest
  `originator: ellmercodex`, experimental-protocol, accept, and user-agent
  headers.
- `codex_request_body()` creates the minimal Responses body with `model`, one
  user text input, fixed instructions, `store: false`, and `stream: true`.
  When selected, effort is forwarded as `reasoning = list(effort = ..., summary
  = "auto")`, matching ellmer's OpenAI Responses mapping.
- `codex_models()` calls the observed `/codex/models` endpoint and normalizes
  model slugs, display names, defaults, supported reasoning efforts, and
  service tiers. It does not bundle a private or copied model catalog.
- `codex_request()` performs HTTP and classifies status failures without exposing
  raw headers or bodies.
- `codex_parse_sse()` handles CRLF/LF framing, `data:` fields, `[DONE]`, and
  bounded JSON parsing. `codex_parse_sse_response()` assembles output deltas and
  requires a terminal event.
- `ellmer-compatibility.R` defines the version-gated `CodexProvider`, dynamic
  credential reference, S7 request/stream/value methods, ordered output-item
  merge, and clone-safe private Chat execution methods. Ellmer's own
  `TurnAccumulator`, tool invocation/callback helpers, async primitives, and
  dangling-request handling remain authoritative.
- `ellmer-compatibility.R` is the sole authoritative tool architecture. Its
  Codex stream merge/content methods assemble ordered function-call items;
  `codex_chat_impl_sync()` and `codex_chat_impl_async()` run the multi-round
  loops; and ellmer remains authoritative for tool invocation, callbacks,
  failures, sync/async modes, cancellation, and tool-result turns. There is no
  second buffered tool parser or manual tool loop in the package.
- `codex_parse_response()` remains as a fallback for ordinary JSON terminal
  payloads.
- `codex_generate()` coordinates auth/refresh, request, and parsing but contains
  no low-level HTTP construction.

This transport does not implement retry loops. Automatically retrying a
possibly accepted generation would obscure the narrow feasibility test and
could consume additional subscription usage.

The live backend omitted `Content-Type` on successful SSE responses. The parser
therefore accepts either a declared `text/event-stream` media type or a safe
`event:`/`data:` body prefix. It never prints the body while making that choice.

## Error taxonomy

| Condition class | Meaning |
|---|---|
| `codex_auth_missing` | No package credential in the configured store |
| `codex_oauth_callback_error` | Callback bind, denial, missing code, or state failure |
| `codex_oauth_timeout` | Browser flow did not return in time |
| `codex_oauth_browser_error` | The system browser could not be opened |
| `codex_token_exchange_error` | Exchange failure or malformed credential response |
| `codex_refresh_error` | Refresh transport failure; authenticate again if persistent |
| `codex_credential_store_error` | Credential conversion or cache configuration failure |
| `codex_account_error` | Required account-routing claim absent |
| `codex_authentication_error` | HTTP 401/403 from the Codex transport |
| `codex_rate_limit_error` | HTTP 429 / subscription or rate limit |
| `codex_model_unavailable_error` | HTTP 404 / model or endpoint unavailable |
| `codex_malformed_request_error` | HTTP 400/409/422 rejection |
| `codex_server_error` | HTTP 5xx |
| `codex_network_error` | Ordinary request transport failure |
| `codex_protocol_changed_error` | Non-JSON or unexpected success response |
| `codex_protocol_error` | Other unexpected HTTP status |
| `codex_generation_error` | SSE failure or error event |
| `codex_incomplete_error` | SSE terminal event reports an incomplete response |
| `codex_chat_argument_error` | Invalid `chat_codex()`/Chat compatibility argument |
| `codex_chat_error` | Sanitized Chat/provider construction failure |
| `codex_ellmer_compatibility_error` | ellmer did not record the expected terminal turn |

Server error details are parsed only from a small nested error object or a
top-level `detail` field, passed through credential and identifier redaction,
and length bounded. Raw response headers and full bodies are never included.

## `ellmer` integration seam

The installed target is exactly `ellmer` 0.4.2. Its public `Chat` object has 25
public methods and no public fields; the complete inventory, exact signatures,
return/state behavior, and helper audit are recorded in
`docs/ellmer-chat-interface.md`.

`chat_codex()` constructs the actual non-exported ellmer `Chat` R6 class with a
version-gated S7 subclass of ellmer's OpenAI provider. The provider reuses
ellmer's OpenAI Responses serializer for every supported input Content and
Turn type, while supplying Codex authentication, mandatory streaming, request
construction, SSE parsing, merge, output conversion, token normalization,
finish metadata, and cost handling.

The Codex endpoint returns useful text in delta events while its terminal
`response.completed$response$output` may be empty. Replacing only the provider
methods is insufficient because ellmer's `chat()` and `chat_async()` normally
use non-streaming value requests. The compatibility module therefore replaces
only the four private Chat execution methods: `chat_impl`, `chat_impl_async`,
`submit_turns`, and `submit_turns_async`. The two chat-loop methods are a small
copy of ellmer's 0.4.2 lifecycle that filters tool-request yields already
emitted at their exact provider position; validation, invocation, callbacks,
async modes, and turn construction still use ellmer helpers. The submit
methods still use ellmer's `TurnAccumulator`, so partial turns, duration,
cancellation, history, finish checks, and structured extraction remain ellmer
semantics. Public methods are never replaced.

The installed private methods are assigned with the Chat enclosing environment
as their function environment. R6 cloning then rewrites `self` and `private` to
the clone. No compatibility closure retains the original Chat. Credential
state is held in a separate mutable reference environment, allowing safe
refresh and refresh-token persistence without OS-keyring re-entry; sharing that
credential cache between a clone and its source does not share Chat turns or
Chat closures.

The response converter retains event order for text, function calls, reasoning,
images, PDFs, and provider/terminal items. Terminal output only fills missing
items and cannot move streamed text across a tool request. Known items become
ellmer Content objects; unknown items become `ContentJson` containing the full
item. Input images, PDFs, tool results, structured schemas, and provider-native
declarations remain on ellmer's serializer path.

`parallel_chat*()` and `batch_chat*()` were audited as part of the public
ellmer surface. They request non-streaming responses or the OpenAI Batch API,
which the Codex subscription endpoint does not provide. The Codex provider
rejects parallel requests with an explicit
`codex_ellmer_parallel_batch_blocker` before network I/O. Batch requests stop in
ellmer's generic provider capability check before network I/O or state-file
creation. This is a documented unsupported boundary, not a false-success
fallback. The stable claim is limited to the `Chat` object and does not include
these helpers.

## Compatibility status and release risks

1. The project deliberately accepts that independent client registration,
   direct subscription transport, and the account-specific model catalog are
   not documented public contracts; the package must disclose this and isolate
   protocol changes.
2. Streaming protocol and model selection without copying another
   client's private catalog.
3. A single, narrowly tested, version-gated ellmer provider/Chat submission
   seam, with the full public Chat lifecycle left to ellmer.
4. httr2 cache behavior and refresh-token rotation tests.
5. Offline-only CRAN tests; no package load, test, example, or check may start
   OAuth or make authenticated requests.

The package addresses the complete Chat surface for the pinned ellmer 0.4.2
release, subject to the undocumented Codex transport. The parallel/batch
helpers remain unsupported by design. The stable claim is therefore a bounded
Chat compatibility claim, not a claim of complete ellmer helper compatibility
or a guarantee that the observed Codex backend will remain available.

# `ellmercodex` technical design

This is the canonical technical description of `ellmercodex`. The
[README](../README.md) is intentionally limited to installation and
user-facing workflows; implementation details, compatibility claims, and
release risks belong here. The exact public `ellmer` Chat inventory is kept in
the companion [compatibility inventory](ellmer-chat-interface.md).

## Scope

This design covers the bounded stable core: `chat_codex()`, explicit browser
login, secure persistence and refresh, SSE Responses calls, offline
availability diagnostics, account-specific model discovery, reasoning effort,
and the interactive `ellmer` Chat interface from 0.5.0 for interactive,
single-conversation operations. The package uses a contract-checked provider
subclass plus one private Chat execution seam because ChatGPT plan usage is
stream-only; it does not replace public Chat methods. The separately exported
ellmer parallel/batch helpers are outside this core contract.

Authentication and transport follow OpenAI's documented "Sign in with ChatGPT"
flow for open-source, locally hosted apps
(<https://developers.openai.com/siwc/token-sharing-open-source>, with its
sign-in, profiles and sessions, models and inference, token reference, errors
and recovery, self-hosted VM, and preview limitation pages). Earlier releases
reused the Codex CLI OAuth client and the undocumented
`chatgpt.com/backend-api/codex` transport; both are gone.

## Components

```text
explicit codex_login()
        |
        v
auth.R: host-id -> state + nonce + PKCE -> browser (auth.openai.com/api/accounts/authorize)
        -> 127.0.0.1:<port>/callback (code, state, issued client_id)
        -> token exchange with the issued client_id
        -> ID token check (JWKS, iss, aud, exp, nonce) -> scope check
        |
        +-------------------------+
        |                         |
        v                         v
credentials.R: credentials.json   auth.R: in-memory auth object
  (0600, atomic, refresh lock)    |
        |                         |
        +------------+------------+
                     v
transport.R: refresh if due -> POST api.openai.com/v1/responses (stream, store=false)
             -> SSE events -> text
                     |
                     v
               codex_generate()

chat_codex() -> ellmer::Chat$new(CodexProvider)
             -> ellmer public Chat lifecycle
             -> private chat/submit compatibility seam
             -> plan-usage body adaptation -> stream-only request
             -> ordered response conversion

chat$stream_async() -> ellmer async stream -> TurnAccumulator -> Chat history
chat$chat_async() -> ellmer async tool loop -> promise return shape
chat$chat_structured_async() -> typed async stream -> ContentJson conversion

registered tools -> ellmer ToolDef execution/callback loop
                 -> ContentToolResult input -> next Responses round

codex_models() -> GET api.openai.com/v1/models, keep visibility == "list"
chat$chat_structured() -> streamed JSON -> repaired ellmer ContentJson turn
codex_available() -> offline dependency/configuration checks by default
```

`R/config.R` is the only location containing endpoints, the dynamic
registration client ID, the scopes and resource, the callback URI, the model
override, and shared transport-header construction. Each value comes from the
documentation above.

## Authentication lifecycle

1. Loading the package defines functions only. It has no authentication,
   browser, credential, or network side effects.
2. Before the first sign-in, `codex_host_id()` creates and persists a stable,
   opaque `ext_agent_host_id` (`urn:uuid:<uuidv4>`) in `host-id`. It is created
   even for `persist = FALSE` because the flow requires it to stay stable per
   host. It is not a credential and is never overwritten by an imported
   credential file.
3. An explicit `codex_login()` calls `codex_oauth_flow()` in `R/auth.R`. It
   generates fresh `state`, `nonce`, and a PKCE S256 verifier, and opens
   `https://auth.openai.com/api/accounts/authorize` with `response_type=code`,
   the scopes `openid profile email offline_access resource.invoke
   chatgpt.tokens.use.direct`, `resource=https://api.openai.com/v1`, and the
   host ID. A first sign-in uses `client_id=dynamic_agent_client` and
   `agent_name_hint=ellmercodex`. A later sign-in reauthorizes the stored
   registration with its issued client ID and `id_token_hint`, without
   `agent_name_hint`.
4. A package-owned `httpuv` listener accepts one request on
   `http://127.0.0.1:<port>/callback` (default port 1455, overridable with
   `ELLMERCODEX_CALLBACK_PORT`) and enforces the `timeout`. The documentation
   requires the IPv4 literal (never `localhost`) and the `/callback` path; only
   the port may vary. httr2's listener is not used because it has no timeout
   and does not expose the callback's `client_id`.
5. The callback must carry the matching `state` and the code. A new
   registration must also return the issued `client_id` (`oaiapp_...`).
6. The code is exchanged at `https://auth.openai.com/api/accounts/oauth/token`
   with `grant_type=authorization_code`, the issued client ID, the verifier,
   the same redirect URI, and the resource. There is no client secret.
7. The ID token is verified with `jose`: the signing key comes from the JWKS
   published in OpenAI's OIDC discovery document, then issuer, audience (the
   issued client ID), expiry, nonce, and subject are checked.
8. The granted scopes must include `chatgpt.tokens.use.direct`. Otherwise
   `codex_plan_scope_error` is signalled and only the registration (issued
   client ID and ID token, no tokens) is stored for a later reauthorization.
9. Access tokens last one hour. Expiry is `expires_in` from the token response
   (falling back to the access-token `exp` claim), with a 60-second refresh
   margin. Refresh posts `grant_type=refresh_token`, the issued client ID, the
   refresh token, and the resource. Refresh tokens rotate and are valid for 30
   days after each refresh.
10. Persistent refreshes run under a lock directory (`refresh.lock`, stale after
    two minutes). Inside the lock the stored file is re-read: if another
    process already rotated the token, its fresh credential is used without a
    request. The documented reauthentication codes (`invalid_grant`,
    `invalid_refresh_token`, `token_expired`, `refresh_token_expired`,
    `refresh_token_invalidated`, `refresh_token_reused`) remove the tokens but
    keep the registration; network and other failures keep the credentials.

The implementation never reads Codex CLI or Pi files, never accepts a supplied
foreign session, and never prints authorization URLs, codes, state, nonce,
verifier, tokens, client IDs, or host IDs. `codex_redact()` covers all of them.

## Credential storage

Dynamic client IDs mean a fixed httr2 `oauth_client()` (whose ID keys httr2's
cache and refresh) no longer fits: the issued client ID is only known after the
first callback. The package therefore owns its storage, in
`tools::R_user_dir("ellmercodex", "config")` or `ELLMERCODEX_HOME`:

- `host-id`: the host's `ext_agent_host_id`.
- `credentials.json`: issued client ID, issuer, subject, email, ID token
  (kept for `id_token_hint`), access and refresh tokens, expiry,
  `earliest_refresh_at`, and granted scopes. It is written to a temporary file
  with mode `0600` and renamed into place; the directory is `0700`. The file
  is plain JSON, as the documentation describes, not obfuscated. On Windows,
  `Sys.chmod()` cannot express owner-only permissions; the user profile's ACLs
  apply.

`persist = FALSE` keeps tokens only in the process-local session; the host ID
is still persisted. No OS keyring is used.

`codex_logout()` revokes the refresh token at the `revocation_endpoint` from
OpenAI's OIDC discovery document (best effort, retried; a failure signals
`codex_revocation_warning`), clears the session, deletes `credentials.json`,
and removes the legacy httr2 cache entry of earlier releases. It keeps
`host-id`. Switching account or workspace is `codex_logout()` followed by
`codex_login()`, which then creates a new registration. `codex_account()`
reports authentication and expiry with a literal account redaction.

## Transport boundary

- `codex_request_headers()` creates only the bearer, `Accept`, and
  `User-Agent` headers. The Codex-specific `ChatGPT-Account-Id`,
  `OpenAI-Beta`, and `originator` headers are gone.
- `codex_request_body()` creates the minimal Responses body with `model`, one
  user text input, fixed instructions, `store: false`, and `stream: true`.
  When selected, effort is forwarded as `reasoning = list(effort = ..., summary
  = "auto")`, matching ellmer's OpenAI Responses mapping.
- `codex_responses_body_adapt()` applies the documented preview limitations to
  every Chat request: `system` input items become `developer` messages;
  function tools are grouped in one `{"type": "namespace", "name": "ellmer"}`
  tool and replayed `function_call` items carry `namespace: "ellmer"`; `store`
  and `stream` are forced; and the prohibited fields (`background`,
  `conversation`, `max_output_tokens`, `max_tool_calls`, `metadata`,
  `moderation`, `multi_agent`, `prompt`, `prompt_cache_retention`,
  `previous_response_id`, `safety_identifier`, `temperature`, `top_logprobs`,
  `top_p`, `truncation`, `user`) raise `codex_chat_argument_error` before any
  request.
- `codex_models()` calls `GET https://api.openai.com/v1/models` with the same
  token, keeps entries with `visibility: "list"` (or no visibility field), and
  normalizes slugs, display names, defaults, supported reasoning efforts, and
  service tiers. The former `client_version` query is gone; the argument is
  deprecated and ignored. An explicitly selected ID absent from the catalog
  still reaches the generation endpoint, which validates it.
- `codex_request()` performs HTTP and classifies status failures without exposing
  raw headers or bodies.
- `codex_parse_sse()` handles CRLF/LF framing, `data:` fields, `[DONE]`, and
  bounded JSON parsing. `codex_parse_sse_response()` assembles output deltas and
  requires a terminal event.
- `ellmer-compatibility.R` defines the contract-checked `CodexProvider`, dynamic
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
possibly accepted generation could duplicate it and consume additional plan
usage.

Only `response.completed` is success. `response.failed` and `error` events
raise `codex_generation_error` (or a plan-specific subclass), and
`response.incomplete` or a stream without a terminal event raises
`codex_incomplete_error` or `codex_protocol_changed_error`. The former
`response.done` terminal event of the Codex backend is no longer accepted.

The old Codex backend omitted `Content-Type` on successful SSE responses, so
the parser still accepts either a declared `text/event-stream` media type or a
safe `event:`/`data:` body prefix. It never prints the body while making that
choice.

## Error taxonomy

| Condition class | Meaning |
|---|---|
| `codex_auth_missing` | No package credential in the configured store |
| `codex_oauth_callback_error` | Callback bind, denial, missing code, or state failure |
| `codex_oauth_timeout` | Browser flow did not return in time |
| `codex_token_exchange_error` | Exchange failure or malformed credential response |
| `codex_refresh_error` | Refresh transport failure; authenticate again if persistent |
| `codex_credential_store_error` | Credential file or host ID unreadable, malformed, or unwritable |
| `codex_plan_scope_error` | `chatgpt.tokens.use.direct` was not granted at sign-in |
| `codex_account_error` | Retained for compatibility; no longer signalled |
| `codex_authentication_error` | HTTP 401/403, `subscription_sharing_invalid_user`, `subscription_sharing_route_not_supported`, `chatpass_v2_*` |
| `codex_plan_ineligible_error` | `subscription_sharing_user_not_eligible` (also `codex_authentication_error`) |
| `codex_rate_limit_error` | HTTP 429 |
| `codex_usage_limit_error` | `subscription_sharing_usage_limit_exceeded` (also `codex_rate_limit_error`) |
| `codex_usage_unavailable_error` | `subscription_sharing_usage_unavailable`, `subscription_sharing_user_unavailable` (also `codex_server_error`) |
| `codex_unsupported_capability_error` | `subscription_sharing_unsupported_capability`, with `param` (also `codex_malformed_request_error`) |
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
Plan error conditions carry the server's `code` and `param` fields. Refresh
and token-exchange conditions carry the OAuth `oauth_error` code.

In Chat requests, an HTTP error raised by httr2 before the stream opens is
converted to the same classes by `codex_stream_next()` on the synchronous
path. The asynchronous path still surfaces httr2's `httr2_http_*` condition,
whose message includes the plan error code from `codex_provider_error_body()`.

## `ellmer` integration seam

The minimum target is `ellmer` 0.5.0, with no upper version limit. Required
contracts and the supported and unavailable operations are recorded in
`docs/ellmer-chat-interface.md`.

`chat_codex()` constructs the actual non-exported ellmer `Chat` R6 class with a
contract-checked S7 subclass of ellmer's OpenAI provider. The provider reuses
ellmer's OpenAI Responses serializer for every supported input Content and
Turn type, while supplying Codex authentication, mandatory streaming, request
construction, SSE parsing, merge, output conversion, token normalization,
finish metadata, and cost handling.

The former Codex endpoint returned useful text in delta events while its
terminal `response.completed$response$output` could be empty; the converter
still tolerates that shape. Replacing only the provider
methods is insufficient because ellmer's `chat()` and `chat_async()` normally
use non-streaming value requests. The compatibility module therefore replaces
only the four private Chat execution methods: `chat_impl`, `chat_impl_async`,
`submit_turns`, and `submit_turns_async`. The two chat-loop methods are a small
adaptation of ellmer's 0.5.0 lifecycle that filters tool-request yields already
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
which ChatGPT plan usage does not provide. The Codex provider
rejects parallel requests with an explicit
`codex_ellmer_parallel_batch_blocker` before network I/O. Batch requests stop in
ellmer's generic provider capability check before network I/O or state-file
creation. This is a documented unsupported boundary, not a false-success
fallback. The stable claim is limited to the `Chat` object and does not include
these helpers.

## Compatibility status and release risks

1. ChatGPT plan usage is an OpenAI preview for open-source and locally hosted
   apps. Its parameter and tool limits, error codes, and eligibility may
   change; the body adapter and error map isolate those rules.
2. The function-tool namespace and the `developer` role are implemented from
   the preview limitations page and must be confirmed with a live tool call.
3. A single, narrowly tested, contract-checked ellmer provider/Chat submission
   seam, with the full public Chat lifecycle left to ellmer.
4. Credential file, lock, and refresh-token rotation tests run offline with
   temporary directories.
5. Offline-only CRAN tests; no package load, test, example, or check may start
   OAuth or make authenticated requests.

The package addresses interactive Chat operations from ellmer 0.5.0 onward,
subject to runtime contract checks and the preview limits of ChatGPT plan
usage. Provider token counting, file management, and parallel/batch helpers
remain unsupported by design. The stable claim is therefore a bounded Chat
compatibility claim, not a claim of complete ellmer helper compatibility.

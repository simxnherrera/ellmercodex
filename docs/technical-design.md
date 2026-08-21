# `ellmercodex` technical design

## Scope

This design began with the proof of concept and now covers the experimental R
package: `chat_codex()`, explicit Pi-style browser login, secure persistence and
refresh, SSE Responses calls, offline availability diagnostics, and an explicit
unsupported result for direct account-specific model discovery. It deliberately
excludes a native `ellmer` provider, structured output, async methods, tools,
and an invented or copied model catalog.

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
credentials.R: keyring       auth object in memory
        |                         |
        +------------+------------+
                     v
transport.R: refresh if due -> stream=true request -> SSE events -> text
                     |
                     v
               codex_generate()

chat_codex() -> ellmer::chat_openai() -> public stream deltas
                                      -> repair terminal assistant turn
                                      -> genuine ellmer Chat

codex_models() -> typed unsupported result (no direct documented catalog)
codex_available() -> offline dependency/configuration checks by default
```

`R/config.R` is the only location containing unstable endpoints, the observed
client identifier, protocol header, callback URI, fallback model, originator,
and request-header construction. Every value is marked as observed rather than
a documented public contract.

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
9. Refresh is form encoded. A rotated refresh token is retained and, when using
   persisted credentials, immediately replaces the old keyring value.

The implementation never reads Codex CLI or Pi files, never accepts a supplied
foreign session, and never prints authorization codes, state, verifier, tokens,
or account identifiers.

## Credential storage

The package defaults to the OS credential store through `keyring`, under
service `ellmercodex` and username `oauth`. It has no plaintext fallback. An
encrypted file under `tools::R_user_dir("ellmercodex", "data")` is available
only with an explicit `ELLMERCODEX_CREDENTIAL_PASSPHRASE`; users can select it
with `ELLMERCODEX_CREDENTIAL_BACKEND=file`. Without a usable keyring or explicit
passphrase, persistence fails with a sanitized error.

`codex_logout()` deletes only that service/username entry and the exact
package-specific encrypted fallback file. `codex_account()` reports
authentication and expiry while replacing the account identifier with a
literal redaction.

The acceptance sequence called `codex_login(persist = FALSE)` first, proved the
in-memory SSE request, and stored only afterward. A genuinely new R process then
read the keyring entry, forced refresh, persisted the refreshed credential, and
made the second successful request.

## Transport boundary

- `codex_request_headers()` creates bearer, account-routing, honest
  `originator: ellmercodex`, experimental-protocol, accept, and user-agent
  headers.
- `codex_request_body()` creates the minimal Responses body with `model`, one
  user text input, fixed instructions, `store: false`, and `stream: true`.
- `codex_request()` performs HTTP and classifies status failures without exposing
  raw headers or bodies.
- `codex_parse_sse()` handles CRLF/LF framing, `data:` fields, `[DONE]`, and
  bounded JSON parsing. `codex_parse_sse_response()` assembles output deltas and
  requires a terminal event.
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
| `codex_credential_store_error` | OS keyring storage/load failure |
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
| `codex_chat_error` | Sanitized failure from the ellmer-backed transport |
| `codex_ellmer_compatibility_error` | ellmer did not record the expected terminal turn |

Server error details are parsed only from a small nested error object or a
top-level `detail` field, passed through credential and identifier redaction,
and length bounded. Raw response headers and full bodies are never included.

## `ellmer` integration seam

The exported `ellmer::chat_openai()` factory successfully creates a standard
`Chat` with the Codex base URL, dynamic credential callback, account header,
honest originator, experimental protocol header, and mandatory streaming. It
must use `service_tier = "default"`; ellmer's `"auto"` default is rejected.

The unmodified seam is incomplete. The backend sends useful text only in
delta events and its terminal `response.completed$response$output` is empty.
Ellmer 0.4.2 visibly streams the deltas, then constructs its final turn from the
empty terminal payload. Consequently `$chat()` returns empty and the assistant
history is empty, breaking the intended multi-turn UX.

`R/chat-codex.R` implements the smallest fallback: `chat_codex()` creates the
public Chat, delegates requests to its public `$stream()`, accumulates emitted
text, and replaces only the empty terminal assistant content. It returns normal
`ellmer_output` values and retains correct multi-turn history. A live two-turn
test passed, and offline tests cover `$chat()`, `$stream()`, and repaired turns.

This is deliberately an instance compatibility layer, not a custom provider. In
ellmer 0.4.2 a native provider requires unexported generics and the unexported
`Chat` constructor; current upstream has already changed both class layout and
generic signatures. A package should pursue an exported upstream finalization
hook; otherwise it needs an explicit ellmer version pin and compatibility tests.

## Compatibility status and release risks

1. The project deliberately accepts that independent client registration and
   the direct subscription transport are not documented public contracts; the
   package must disclose this and isolate protocol changes.
2. Streaming protocol and model selection without copying another
   client's private catalog.
3. An exported-only `ellmer` integration seam.
4. Keyring behavior across supported operating systems and refresh-token
   rotation tests.
5. Offline-only CRAN tests; no package load, test, example, or check may start
   OAuth or make authenticated requests.

The package addresses items 1, 2, 3, and 5 for its deliberately narrow text-chat
surface on ellmer 0.4.x. Account-specific model discovery remains unsupported
rather than inferred. Cross-platform keyring coverage and future ellmer
compatibility remain release-maintenance work; neither changes the decision to
retain the direct transport.

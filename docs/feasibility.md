# `ellmercodex` feasibility study

Status: investigation, offline checks, Pi-style OAuth, buffered SSE transport,
keyring persistence, forced refresh, genuine-process restart, and a working
multi-turn `chat_codex()` proof of concept are complete. An experimental R
package now ports those pieces with offline tests, model/availability
diagnostics, documentation, and CI. Sources were inspected on 2026-08-20.

The package implementation preserves the support boundary below while accepting
it as an experimental compatibility risk. See `docs/research-risk-review.md`
for the package-phase review and release posture.

## Conclusion and recommendation

The proposed pure-R subscription transport is **technically feasible with
streaming**.
Pi, OpenCode, OpenClaw, CortexKit, and OpenAI Codex converge on the same browser
authorization-code flow with PKCE, token refresh shape, account claim, and direct
Codex Responses transport. R has all of the required primitives in `openssl`,
`httpuv`, `httr2`, `jsonlite`, and `keyring`.

The authorized next phase is a **technical go**: browser OAuth succeeded; a
minimal pure-R SSE implementation buffered `Hello from R`; the credential was
then stored in the macOS keyring; and a genuinely new R process restored it,
forced refresh, persisted the refreshed credential, and buffered `Still
working`.

The package decision is **go for an explicitly experimental release using the
direct transport**. OpenAI's official documentation supports
subscription-backed ChatGPT sign-in for Codex and presents `codex app-server`
as a documented product-integration protocol. It does not document the raw
OAuth endpoints, the public client identifier's use by arbitrary third-party
native clients, or `chatgpt.com/backend-api/codex/responses` as a supported
public contract. The project accepts that as a compatibility and maintenance
risk; it is not presented as evidence that the approach is either authorized or
forbidden.

The live PoC followed Pi's mechanics while identifying the client honestly as
`ellmercodex`; that authorization was accepted. Releases must continue to use
an honest originator, package-owned credentials, explicit user authentication,
and prominent experimental-status disclosure. Never impersonate Pi or Codex.

The transport and PoC integration uncertainties are resolved: every current
client inspected uses `stream: true`, the live backend explicitly requires it,
buffered SSE works in pure R, and a thin compatibility layer produces correct
`ellmer` return values and history. Production-grade support remains out of
scope for the experimental release rather than blocking it.

## Official documentation and policy findings

Verified from current OpenAI documentation:

- [Codex authentication](https://learn.chatgpt.com/docs/auth) documents
  subscription-backed ChatGPT sign-in and separately billed API-key access. It
  documents automatic refresh and local credential-storage choices for Codex.
- [Codex app-server](https://learn.chatgpt.com/docs/app-server) documents managed
  `chatgpt` browser login and `chatgptDeviceCode` login. Its host-supplied
  `chatgptAuthTokens` mode is experimental and makes the host responsible for
  refresh.
- [Codex as a platform](https://learn.chatgpt.com/blog/codex-as-a-platform), dated
  2026-08-19, calls app-server a documented client protocol and identifies the
  CLI, SDKs, and app-server as the supported integration layers around the open
  harness.
- [Codex access tokens](https://learn.chatgpt.com/docs/enterprise/access-tokens)
  are currently documented for trusted Business and Enterprise CLI/app-server
  workflows, not as a general consumer OAuth registration mechanism.
- [Codex pricing](https://learn.chatgpt.com/docs/pricing) says Codex access is
  included across listed ChatGPT plans and is subject to plan-specific usage
  limits, approximate five-hour windows, possible weekly limits, and workspace
  controls.
- [Feature maturity](https://learn.chatgpt.com/docs/feature-maturity) defines
  experimental interfaces as changeable and not recommended for production.

The app-server documentation also asks clients to identify themselves with
`clientInfo.name` and tells enterprise integrations to contact OpenAI about its
known-client list. The reviewed official sources do **not** say whether an
independent native client may reuse the client identifier seen in open source,
whether it must obtain a distinct registration, or whether the direct backend is
supported. Absence of a statement is neither permission nor prohibition.

A secondary source is relevant but is not policy authority: [Simon Willison's
April 2026 report](https://simonwillison.net/2026/Apr/23/gpt-5-5/) quotes OpenAI
leadership as welcoming subscription use in other coding agents and explicitly
mentions Pi and OpenCode. It supports the inference that Pi-style interoperability
is intentional, but it does not turn the raw endpoints into a documented public
API.

## Implementation evidence

All revisions below were inspected at real code paths rather than from README
claims.

- OpenAI Codex, commit
  [`21facf227366ae68589cf7567db917a3ba2dbd9a`](https://github.com/openai/codex/commit/21facf227366ae68589cf7567db917a3ba2dbd9a):
  [`codex-rs/login/src/auth/manager.rs`](https://github.com/openai/codex/blob/21facf227366ae68589cf7567db917a3ba2dbd9a/codex-rs/login/src/auth/manager.rs)
  defines the observed native-client identifier and token management;
  [`codex-rs/login/src/server.rs`](https://github.com/openai/codex/blob/21facf227366ae68589cf7567db917a3ba2dbd9a/codex-rs/login/src/server.rs)
  implements browser login, PKCE, state, and the loopback callback.
- Pi, commit
  [`5cd93f688aaab89dbb6dfa4aca535f21796ae185`](https://github.com/earendil-works/pi/commit/5cd93f688aaab89dbb6dfa4aca535f21796ae185):
  [`openai-codex.ts`](https://github.com/earendil-works/pi/blob/5cd93f688aaab89dbb6dfa4aca535f21796ae185/packages/ai/src/auth/oauth/openai-codex.ts)
  implements OAuth; [`openai-codex-responses.ts`](https://github.com/earendil-works/pi/blob/5cd93f688aaab89dbb6dfa4aca535f21796ae185/packages/ai/src/api/openai-codex-responses.ts)
  implements the transport.
- OpenCode, commit
  [`5e75e5e9901f0d178f425bfb47f1bd46cbe78a59`](https://github.com/anomalyco/opencode/commit/5e75e5e9901f0d178f425bfb47f1bd46cbe78a59):
  [`packages/opencode/src/plugin/openai/codex.ts`](https://github.com/anomalyco/opencode/blob/5e75e5e9901f0d178f425bfb47f1bd46cbe78a59/packages/opencode/src/plugin/openai/codex.ts).
- OpenClaw, commit
  [`e78b9d3ce4aa32ecd84cf5c961ff8cd2db48f6db`](https://github.com/openclaw/openclaw/commit/e78b9d3ce4aa32ecd84cf5c961ff8cd2db48f6db):
  [authorization](https://github.com/openclaw/openclaw/blob/e78b9d3ce4aa32ecd84cf5c961ff8cd2db48f6db/extensions/openai/openai-chatgpt-oauth-authorization.runtime.ts),
  [token handling](https://github.com/openclaw/openclaw/blob/e78b9d3ce4aa32ecd84cf5c961ff8cd2db48f6db/extensions/openai/openai-chatgpt-oauth-token.runtime.ts),
  and [Responses transport](https://github.com/openclaw/openclaw/blob/e78b9d3ce4aa32ecd84cf5c961ff8cd2db48f6db/packages/ai/src/providers/openai-chatgpt-responses.ts).
- CortexKit OpenAI Auth, commit
  [`9bf8f4c3e9cfa8a9a073b293625157787e100afe`](https://github.com/cortexkit/openai-auth/commit/9bf8f4c3e9cfa8a9a073b293625157787e100afe):
  [`packages/opencode/src/core/oauth.ts`](https://github.com/cortexkit/openai-auth/blob/9bf8f4c3e9cfa8a9a073b293625157787e100afe/packages/opencode/src/core/oauth.ts)
  and [`packages/opencode/src/index.ts`](https://github.com/cortexkit/openai-auth/blob/9bf8f4c3e9cfa8a9a073b293625157787e100afe/packages/opencode/src/index.ts).
- Simon Willison's plugin, commit
  [`ba5b0234b9850440b8a4a4eb97faa9667dbe0761`](https://github.com/simonw/llm-openai-via-codex/commit/ba5b0234b9850440b8a4a4eb97faa9667dbe0761):
  [`llm_openai_via_codex.py`](https://github.com/simonw/llm-openai-via-codex/blob/ba5b0234b9850440b8a4a4eb97faa9667dbe0761/llm_openai_via_codex.py).
  This implementation borrows the Codex CLI credential file, so it is evidence
  only and is explicitly excluded from the PoC design.

Shared observed behavior is authorization-code OAuth with PKCE S256, scope
`openid profile email offline_access`, exact redirect URI
`http://localhost:1455/auth/callback`, form-encoded exchange/refresh, the
namespaced ChatGPT account claim, and the Codex Responses backend. Pi binds the
server socket to `127.0.0.1` while preserving `localhost` in the registered URI;
the PoC does the same. Each reputable independent client supplies its own
`originator`; the PoC supplies `ellmercodex` and never claims to be another
client.

Project-specific behavior must not be conflated with the common contract.
Account-claim fallbacks differ, model catalogs differ, session header spelling
differs, and WebSocket protocol values have changed. CortexKit's multi-account
routing and Simon's credential-file reuse are intentionally not copied.

## `ellmer` findings

The installed version is `ellmer` 0.4.2. The inspected upstream release is
[`v0.4.2`](https://github.com/tidyverse/ellmer/releases/tag/v0.4.2); upstream
`main` was commit
[`19be478ebf1a2e5d2db96a8aeaca71592c8d3f26`](https://github.com/tidyverse/ellmer/commit/19be478ebf1a2e5d2db96a8aeaca71592c8d3f26),
version 0.4.2.9000.

In 0.4.2, `Provider` is exported but `Chat` and provider dispatch generics such
as `chat_request`, `chat_body`, `stream_parse`, and `value_turn` are not. An
in-memory external subclass test worked only by registering methods against
`ellmer:::` symbols. That is not an acceptable stable package seam. See
[`R/provider.R` at v0.4.2](https://github.com/tidyverse/ellmer/blob/v0.4.2/R/provider.R)
and [`R/chat.R` at v0.4.2](https://github.com/tidyverse/ellmer/blob/v0.4.2/R/chat.R).

Upstream `main` exports `Chat` and a new `Model` class, but still does not export
the provider generics; their signatures have also changed. A custom subclass
would therefore carry high version-coupling risk.

The implemented seam wraps public `ellmer::chat_openai()`, which already speaks
the Responses shape and accepts `base_url`, `credentials`, and additional
headers. A narrow instance compatibility layer collects ellmer's emitted text
and restores it to the final assistant turn when the subscription terminal
payload omits `response$output`. Structured output uses the same streamed
fallback and installs `ContentJson` before ellmer's normal type conversion. This
avoids subclassing unexported provider generics while returning a genuine
`ellmer` `Chat`.

Live `$chat()` tests returned `acknowledged` on the first turn, recalled `amber`
on the second, and retained four user/assistant turns. `$stream()` and terminal
history repair, structured conversion, an offline end-to-end registered
ellmer tool loop, and the asynchronous Chat methods are also covered. Async
tool modes delegate to ellmer's async tool loop; the package still gates the
whole adapter to ellmer 0.4.x.

## Risks and assumptions

- The observed public client identifier appears intended for Codex native login;
  a distinct registration path for `ellmercodex` is not documented.
- The authorization and backend URLs, account claim, `originator` semantics, and
  `OpenAI-Beta: responses=experimental` are unstable observations.
- The exact callback URI spelling and port are compatibility requirements.
- Refresh-token rotation must be persisted immediately.
- Eligibility, workspace administration, usage limits, and model availability
  remain account-specific.
- A non-streaming request is rejected even when OAuth succeeds; SSE is required.
- Successful OAuth demonstrates current login compatibility for one account; it
  does not establish policy approval or production stability.
- `ellmer::chat_openai()` must use `service_tier = "default"`; its default
  `"auto"` is rejected by the subscription backend.
- The backend streams output deltas but returns an empty terminal
  `response$output`. `ellmer` 0.4.2 therefore prints the deltas but replaces its
  final assistant turn with empty content unless the PoC compatibility layer is
  installed on the Chat instance.

## Acceptance evidence

Offline checks pass without network or credential access. The first live login
initially exposed a local callback-parser bug: `httpuv` includes a leading `?` in
`QUERY_STRING`, so the first field was parsed as `?code`. A real localhost
fixture reproduced the exact missing-code symptom; normalizing the prefix made
that regression test pass.

After the fix, explicit Pi-style browser OAuth completed successfully with
`originator = ellmercodex`. The credential stayed in memory and no secret or
account identifier was printed. The first exploratory request used `store:
false` and `stream: false`; it returned:

```text
HTTP 400
Stream must be set to true
```

No result was fabricated from that response. In the explicitly authorized next
phase, the request changed to `stream: true`, buffered the SSE events, tolerated
the backend's missing `Content-Type` header through SSE prefix detection, and
returned:

```text
Hello from R
```

Only then was the credential written to the macOS keyring. That R process was
terminated without saving its workspace. A new `Rscript --vanilla` process
loaded only `poc/run.R`, restored the PoC credential, forced a token refresh, and
returned:

```text
restored-and-refreshed: TRUE
Still working
```

The exported `ellmer::chat_openai()` seam was also tested live. Its default
`service_tier = "auto"` produced a sanitized HTTP 400; setting it to `"default"`
made streaming succeed visibly. However, `$chat()` returned an empty string and
the final assistant turn had zero text characters. A protocol-only probe
confirmed that the terminal `response.completed` payload has zero output items;
the usable text exists only in preceding delta events. The public factory is
therefore insufficient by itself. The implemented Codex compatibility layer
buffers those public-stream deltas and repairs the final assistant turn. A live
two-turn `chat_codex()` test then returned `acknowledged`, recalled `amber`, and
retained four turns.

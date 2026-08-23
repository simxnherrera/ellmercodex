# Package landscape: `ellmercodex`

Research checked 2026-08-23 against the repository's `DESCRIPTION`, README, and
design notes, then against primary sources only: CRAN package records, official
GitHub repositories/source, and first-party documentation.

## Bottom line

Yes: the core idea already exists in one close R package, [`llm.api`](https://CRAN.R-project.org/package=llm.api).
It exposes an `openai_codex` provider that logs in with a ChatGPT subscription,
caches and refreshes the token, and sends streamed Codex Responses requests.
However, it is not an `ellmercodex` clone. `llm.api` deliberately reimplements
a small provider-neutral `chat()`/`agent()` API with base R, `curl`, `jsonlite`,
and `tinyoauth`; it does not depend on or return `ellmer::Chat`.
[`ellmercodex`](https://github.com/simxnherrera/ellmercodex) is differentiated by
being an `ellmer` companion: its stated contract is a real `ellmer` 0.4.2
`Chat`, with ellmer history, streaming, structured output, tools, async methods,
callbacks, cloning, multimodal content, model discovery, and reasoning effort,
backed by a direct subscription transport.

The most accurate positioning is therefore: **not first R package to use
Codex subscription access, but plausibly the first focused R package found in
this search whose product boundary is native `ellmer::Chat` compatibility.**
That last point is a scoped research finding, not a claim that no unindexed or
private implementation exists.

## Comparison target

The local package describes itself as an independent third-party integration
between `ellmer` and observed subscription-backed Codex authentication and
streaming behavior. It pins `ellmer` to 0.4.2 and explicitly says it does not
invoke the Codex CLI at runtime. Its README presents explicit browser login,
package-scoped credential storage, direct R HTTPS/SSE transport, account-specific
model discovery, tool calling, structured output, async/cancellation, cloning,
and image/PDF content. The package also discloses that the subscription
transport is an undocumented compatibility surface. [DESCRIPTION](https://github.com/simxnherrera/ellmercodex/blob/main/DESCRIPTION), [README](https://github.com/simxnherrera/ellmercodex/blob/main/README.md), [technical design](https://github.com/simxnherrera/ellmercodex/blob/main/docs/technical-design.md)

## Closest R implementations

### `llm.api` — closest functional match

`llm.api` is on CRAN and its package description explicitly includes OpenAI
Codex subscription endpoints. Its README exports `openai_codex_login()` and
`chat_openai_codex()`, supports a generic `chat()` and an agent loop with tool
use, and describes device-code login with token caching and refresh through
`tinyoauth`. [CRAN record](https://CRAN.R-project.org/package=llm.api), [repository README](https://github.com/cornball-ai/llm.api#openai-codex-chatgpt-subscription)

The implementation overlap is substantial: both packages construct Codex
Responses bodies, force streaming, attach a ChatGPT account identifier, parse
SSE output, normalize usage, and support subscription authentication without an
OpenAI API key. The `llm.api` provider source makes those details explicit,
including the `/codex/responses` path, `stream = TRUE`, `store = FALSE`, the
`originator` header, and function-call/web-search handling. [Codex provider source](https://github.com/cornball-ai/llm.api/blob/main/R/openai-codex.R)

The meaningful difference is the public seam. `llm.api` says its API design is
derived from ellmer but reimplemented with minimal dependencies; its Codex
wrapper returns the package's own result/history shape and its agent loop owns
tool dispatch. [llm.api DESCRIPTION](https://github.com/cornball-ai/llm.api/blob/main/DESCRIPTION), [llm.api agent source](https://github.com/cornball-ai/llm.api/blob/main/R/agent.R)
[`ellmercodex`](https://github.com/simxnherrera/ellmercodex) instead
keeps ellmer as the source of truth for the public Chat lifecycle and installs a
version-gated provider/transport seam underneath it. `ellmercodex` therefore
targets callers who already use ellmer code and expect `Chat$chat()`,
`Chat$stream()`, `Chat$chat_structured()`, tool registration, callbacks, and R6
cloning to behave as ellmer methods.

There is also a model-catalog distinction: `llm.api` documents a small explicit
Codex model set and a default model, while `ellmercodex` documents authenticated,
account-specific model discovery and validates reasoning-effort choices against
the returned catalog. [llm.api README](https://github.com/cornball-ai/llm.api#openai-codex-chatgpt-subscription), [ellmercodex README](https://github.com/simxnherrera/ellmercodex#choose-a-model)

### `corteza` — an R agent built on `llm.api`

[`corteza`](https://github.com/cornball-ai/corteza) is an adjacent R package and
CLI. Its README says that `openai_codex` uses a ChatGPT subscription and that
the package can run an in-session or terminal agent with tools such as shell,
file, and R execution. It consumes `llm.api`; it is an agent runtime, not an
ellmer provider and not a drop-in replacement for an ellmer Chat. [Corteza README](https://github.com/cornball-ai/corteza#chatgpt-subscription-codex-no-api-key), [corteza dependency/design comparison](https://github.com/cornball-ai/corteza#landscape)

## Official OpenAI/Codex implementations

OpenAI's own Codex repository now includes a Python SDK and the app-server
protocol. The SDK starts Codex threads and turns, streams progress, and controls
workspace access; published Python builds include a pinned Codex CLI runtime.
Its public examples support ChatGPT browser login, device-code login, and API-key
login. This is a first-party, much broader coding-agent surface, but it is
Python/app-server based rather than an R HTTP client or an ellmer provider. [Official Python SDK README](https://github.com/openai/codex/blob/main/sdk/python/README.md), [official SDK documentation](https://developers.openai.com/codex/sdk/)

The official app-server documentation confirms the same conceptual boundary:
ChatGPT-managed OAuth is a supported Codex auth mode, with browser and device
flows, persisted/automatically refreshed tokens, account inspection, logout, and
rate-limit APIs. `ellmercodex` overlaps on subscription login and account-scoped
requests, but intentionally exposes a simple R chat object rather than Codex's
threads, sandbox, approvals, and JSON-RPC agent controls. [Codex app-server auth](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#auth-endpoints)

## Other direct subscription clients

Pi's TypeScript AI layer has a built-in `openai-codex` provider. Its source
registers the Codex backend URL, marks the provider as a ChatGPT Plus/Pro
subscription provider, loads a Codex model catalog, and uses a dedicated OAuth
flow. The OAuth source includes PKCE, browser callback port 1455, device-code
endpoints, token exchange/refresh, and account-id extraction. This is a close
transport-level analogue, but Pi is a Node/TypeScript coding-agent harness with
its own provider and session abstractions, not an R package or ellmer adapter.
[Pi provider source](https://github.com/badlogic/pi-mono/blob/main/packages/ai/src/providers/openai-codex.ts), [Pi OAuth source](https://github.com/badlogic/pi-mono/blob/main/packages/ai/src/auth/oauth/openai-codex.ts), [Pi provider documentation](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/README.md#providers--models)

OpenCode also has third-party plugins that replace or extend its OpenAI provider
with ChatGPT Plus/Pro OAuth, Codex request rewriting, model filtering, and (in
some implementations) account fallback and quota tracking. These demonstrate
that the subscription transport is being adapted by several agent ecosystems,
but they are plugins for an existing coding agent rather than general-purpose
language bindings. [CortexKit OpenCode auth plugin](https://github.com/cortexkit/openai-auth), [OpenCode Codex auth plugin](https://github.com/numman-ali/opencode-openai-codex-auth)

## Relationship to upstream `ellmer`

Upstream `ellmer` already has a first-party OpenAI Responses provider and a rich
`Chat` object with streaming, structured output, tools, async methods, and
history. But its `chat_openai()` documentation says it uses the OpenAI API and
requires a developer account/API access; a ChatGPT Plus membership does not
grant that API access. Its `chat_openai_compatible()` function targets
chat-completions-compatible APIs, not the subscription-backed Codex endpoint.
[`ellmercodex`](https://github.com/simxnherrera/ellmercodex) therefore fills a
specific gap between the two: preserve ellmer's native Chat semantics while
providing the separate ChatGPT/Codex subscription authentication and streaming
transport. [ellmer `chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html), [ellmer `chat_openai_compatible()`](https://ellmer.tidyverse.org/reference/chat_openai_compatible.html), [ellmer `Chat`](https://ellmer.tidyverse.org/reference/Chat.html)

## Practical conclusion

`llm.api` is the direct competitor to acknowledge prominently. Its existence and
the overlap above support the inference that the market need is real, but the
strongest remaining differentiator for `ellmercodex` is not “R can use a
ChatGPT subscription”; that already exists. It is “an existing ellmer user can
keep the native ellmer Chat object and its behavior while authenticating
directly to Codex.” The README should continue to make that distinction, the
undocumented-transport caveat, and the deliberate lack of CLI/runtime dependency
explicit. [llm.api](https://CRAN.R-project.org/package=llm.api), [ellmer Chat](https://ellmer.tidyverse.org/reference/Chat.html), [ellmercodex README](https://github.com/simxnherrera/ellmercodex#stable-core-compatibility-scope)

### Sources reviewed

- [Local package DESCRIPTION](https://github.com/simxnherrera/ellmercodex/blob/main/DESCRIPTION) and [README](https://github.com/simxnherrera/ellmercodex/blob/main/README.md)
- [`llm.api` on CRAN](https://CRAN.R-project.org/package=llm.api), [Codex source](https://github.com/cornball-ai/llm.api/blob/main/R/openai-codex.R), and [package DESCRIPTION](https://github.com/cornball-ai/llm.api/blob/main/DESCRIPTION)
- [Official OpenAI Codex repository](https://github.com/openai/codex), [Python SDK](https://github.com/openai/codex/tree/main/sdk/python), and [app-server auth documentation](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#auth-endpoints)
- [Pi Codex provider](https://github.com/badlogic/pi-mono/blob/main/packages/ai/src/providers/openai-codex.ts)
- [Upstream ellmer OpenAI provider documentation](https://ellmer.tidyverse.org/reference/chat_openai.html)

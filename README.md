# ellmercodex

`ellmercodex` is an experimental, independent R package that connects
[`ellmer`](https://ellmer.tidyverse.org/) text chats to observed
subscription-backed Codex behavior.

> **Support and policy warning**
>
> The direct OAuth endpoints, native client identifier, request headers, and
> `chatgpt.com/backend-api/codex/responses` transport used here are observed
> compatibility behavior, not a documented public integration contract for
> third-party packages. This package deliberately retains that direct route to
> provide a pure-R integration similar to other independent coding clients.
> Treat it as experimental and potentially breakable, not as OpenAI-endorsed
> software or evidence of policy approval.

The package never authenticates, opens a browser, reads credentials, or makes a
network request while loading. Its tests, examples, and CI are offline.

## Status

The package currently provides:

- explicit browser OAuth with PKCE and state validation;
- package-scoped keyring persistence, refresh-token rotation, and logout;
- an explicitly enabled encrypted `tools::R_user_dir()` fallback when an OS
  keyring cannot be used;
- mandatory streaming request construction and buffered SSE parsing;
- a narrow `ellmer::chat_openai()` compatibility layer that preserves streamed
  final text and multi-turn history; and
- offline availability checks, redacted diagnostics, and an honest unsupported
  result for direct account-specific model discovery.

Text chat is version-gated to `ellmer >= 0.4.2` and `< 0.5.0`. Structured
output, tools, asynchronous chat methods, a native Provider subclass, and a
production support contract are out of scope.

## Installation

After a CRAN release, install the package with:

```r
install.packages("ellmercodex")
```

To install a source tarball built from this checkout:

```sh
R CMD build .
R CMD INSTALL ellmercodex_0.1.0.tar.gz
```

## Offline usage

These examples are safe during package checks and do not inspect credentials:

```r
library(ellmercodex)

codex_available()

models <- codex_models()
attr(models, "supported")
attr(models, "reason")
```

`codex_models()` does not copy a catalog from another client or confuse API
models with subscription eligibility. OpenAI currently documents account-aware
`model/list` through Codex app-server, but no equivalent direct discovery
contract for this package's transport. Pass a model explicitly to
`chat_codex()` when appropriate. The centralized development fallback can be
overridden with `ELLMERCODEX_MODEL`.

## Explicit live use

The following is intentionally not run by package checks. It opens a browser
and uses the experimental transport only after an explicit call:

```r
if (interactive()) {
  codex_login()

  chat <- chat_codex(
    system_prompt = "Be concise.",
    model = Sys.getenv("ELLMERCODEX_MODEL", "gpt-5.6-luna")
  )

  chat$chat("Remember that the codeword is amber. Reply: acknowledged")
  chat$chat("What was the codeword?")
}
```

Explicitly inspect this package's credential backend and return only a redacted
account summary with `codex_account()`. Remove only this package's credential
with `codex_logout()`. The package never reads `~/.codex/auth.json` or another
application's stored session.

Use `codex_login(persist = FALSE)` to keep a credential only in the current R
process. That process-local session remains available to `chat_codex()` and is
cleared by `codex_logout()`; it is never written to disk or the OS keyring.

The OS keyring is the default credential backend. An encrypted file fallback
under `tools::R_user_dir("ellmercodex", "data")` is available only when
`ELLMERCODEX_CREDENTIAL_BACKEND=file` and
`ELLMERCODEX_CREDENTIAL_PASSPHRASE` is explicitly set. No plaintext fallback is
provided.

## Compatibility checks

The installed package includes an opt-in live acceptance script at
`system.file("manual-tests", "live.R", package = "ellmercodex")`. It is never
run by `R CMD check`. Maintainers can use it before a release by setting
`ELLMERCODEX_RUN_LIVE_TESTS=true`; it checks explicit authentication, two-turn
text chat, and retained history without printing credentials.

Ordinary tests and examples remain fixture-only. They do not start OAuth,
inspect the keyring, contact OpenAI, or rely on a currently available model.

## Public API

The exported API is exactly:

- `codex_login()`
- `codex_logout()`
- `codex_account()`
- `codex_models()`
- `codex_available()`
- `chat_codex()`

See [the feasibility study](docs/feasibility.md),
[technical design](docs/technical-design.md), and
[release-risk review](docs/research-risk-review.md) for the documented versus
observed boundary, the accepted direct-transport decision, and the remaining
compatibility risks.

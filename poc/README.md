# Pure-R `chat_codex()` proof of concept

This directory is intentionally not an R package. It implements the smallest
pure-R experiment needed to test a subscription-backed `ellmer` Chat, Pi-style
browser OAuth, OS-keyring persistence, refresh, and SSE Responses requests.

The direct OAuth and `chatgpt.com/backend-api/codex/responses` transport are
observed compatibility behavior, not a documented public API contract. See
`docs/feasibility.md` before running live authentication.

## Live result

On 2026-08-20, Pi-style browser OAuth succeeded with the client identifying
itself as `ellmercodex`. The backend rejected `stream: false`, so the authorized
next phase implemented minimal buffered SSE with `stream: true`.

The complete acceptance sequence then passed:

```text
Hello from R
restored-and-refreshed: TRUE
Still working
```

The credential was stored in the macOS keyring only after the first successful
generation. The second result came from a genuinely new R process after a forced
refresh.

The final compatibility layer also passed a live multi-turn `ellmer` test:

```text
first: acknowledged
second: amber
turns: 4
```

## Use `chat_codex()`

```r
source("poc/run.R")

# Explicit first-use login opens the browser and saves the resulting credential
# in the OS keyring. chat_codex() never opens a browser itself.
codex_login()

# Later calls restore and refresh that credential automatically.
chat <- chat_codex(
  system_prompt = "Be concise.",
  echo = "output"
)

chat$chat("Remember that the codeword is amber. Reply: acknowledged")
chat$chat("What was the codeword?")
```

`chat_codex()` returns an `ellmer` `Chat`, not a bespoke transport object.
`$chat()`, `$stream()`, turn inspection, and multi-turn history work in this
PoC. The compatibility layer does not yet promise structured output, async
methods, or tool calling.

## Offline validation

```sh
Rscript poc/validate-offline.R
```

Sourcing `poc/run.R` never opens a browser and never initiates authentication.

## Live test

Run from an interactive R process:

```r
source("poc/run.R")

# The browser opens only here. For the first test, keep credentials in memory.
auth <- codex_login(persist = FALSE)
codex_account(auth)

result <- codex_generate("Return exactly: Hello from R", auth = auth)
print(result)

# Persist only after the in-memory request succeeds.
codex_credentials_store(auth)
```

Then exit R completely and start a new process:

```r
source("poc/run.R")
auth <- codex_auth(force_refresh = TRUE)
result <- codex_generate("Return exactly: Still working", auth = auth)
print(result)
```

Remove only this PoC's stored credential with:

```r
codex_logout()
```

No code reads Codex CLI files or reuses another application's stored session.

## `ellmer` seam result

`ellmer::chat_openai()` can construct and send the Codex request using exported
arguments when `service_tier = "default"`. The subscription terminal event has
an empty `response$output`, so unmodified ellmer 0.4.2 discards its accumulated
deltas. `poc/ellmer.R` supplies the narrow compatibility layer: it delegates to
the public factory and streaming method, buffers the emitted text, and repairs
the terminal assistant turn. Live `$chat()` return values and multi-turn history
now pass.

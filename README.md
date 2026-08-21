# ellmercodex

`ellmercodex` lets you use a Codex subscription from R through an
[`ellmer`](https://ellmer.tidyverse.org/) chat interface.

This is an independent, experimental integration. It uses compatibility
behavior observed in Codex clients rather than a documented third-party API,
so it may stop working if and when the upstream service changes. It is not affiliated
with or endorsed by OpenAI.

## Install

Install the current tagged release from GitHub with [`pak`](https://pak.r-lib.org/):

```r
install.packages("pak")
pak::pak("simxnherrera/ellmercodex@v0.1.1")
```

## Quick start

Load the package and sign in. `codex_login()` opens a browser for the sign-in
flow and saves the package's credential for later sessions by default.

```r
library(ellmercodex)

codex_login()

chat <- chat_codex(
  system_prompt = "Be concise and helpful."
)

chat$chat("Explain why reproducible examples matter in R packages.")
chat$chat("Now summarize that in one sentence.")
```

The returned object is a regular `ellmer` `Chat`, so each `$chat()` call keeps
the conversation history. Use `$stream()` when you want streamed output:

```r
chat$stream("Give me three ideas for naming an R package.")
```

If you have already signed in and the credential is still available, you can
skip `codex_login()` and call `chat_codex()` directly. The package refreshes a
stored credential when needed.

## Choose a model

Model availability depends on your account and workspace. Once authenticated,
the Codex catalog can be queried directly:

```r
models <- codex_models()
models[c("id", "display_name", "default_reasoning_effort",
         "supported_reasoning_efforts")]
```

Select a model explicitly when needed:

```r
chat <- chat_codex(model = models$id[[1]])
```

You can also set `ELLMERCODEX_MODEL` and omit the `model` argument:

```r
Sys.setenv(ELLMERCODEX_MODEL = "gpt-5.6-luna")
chat <- chat_codex()
```

Reasoning effort uses ellmer's `reasoning_effort` parameter and is forwarded
unchanged as Codex Responses `reasoning.effort`. Prefer one of the values
advertised for the selected model:

```r
chat <- chat_codex(model = models$id[[1]], effort = "high")

# Equivalent ellmer-style parameter configuration:
chat <- chat_codex(
  model = models$id[[1]],
  params = ellmer::params(reasoning_effort = "high")
)
```

## Authentication and credentials

Inspect the current sign-in state with a redacted account summary:

```r
codex_account()
```

To keep a credential only for the current R process, use:

```r
codex_login(persist = FALSE)
```

Sign out and remove the credential owned by this package with:

```r
codex_logout()
```

By default, credentials are stored in the operating system's keyring. The
package does not read credentials belonging to Codex CLI or other applications.

## Structured output

`chat_codex()` preserves ellmer's structured-output interface. Use any
ellmer `type_*()` schema; the request is streamed to satisfy the Codex
subscription transport, then the streamed JSON is repaired into the assistant
turn before ellmer converts it:

```r
chat <- chat_codex(model = models$id[[1]])
chat$chat_structured(
  "My name is Susan and I'm 13 years old.",
  type = ellmer::type_object(
    name = ellmer::type_string(),
    age = ellmer::type_integer()
  )
)
```

## Current scope

The current release supports ordinary text chats, text streaming, structured
output, model parameters, reasoning effort, and multi-turn history with
`ellmer >= 0.4.2` and `< 0.5.0`. Tool calls and asynchronous chat methods are
not supported by the Codex compatibility layer yet.

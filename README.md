# ellmercodex

`ellmercodex` lets you use a Codex subscription from R through an
[`ellmer`](https://ellmer.tidyverse.org/) chat interface.

The package does not invoke or require the Codex CLI at runtime. Authentication,
model discovery, HTTPS requests, and SSE streaming are implemented directly in
R.

The stable package contract is deliberately bounded to the complete public
`ellmer` 0.4.2 `Chat` object for interactive, single-conversation operations.
The underlying subscription authentication and Responses transport are
compatibility behavior observed in Codex clients rather than a documented
third-party API, so upstream changes may still require a package update. This
package is independent and is not affiliated with or endorsed by OpenAI.

## Install

Install the current tagged release from GitHub with [`pak`](https://pak.r-lib.org/):

```r
install.packages("pak")
pak::pak("simxnherrera/ellmercodex@v0.1.6")
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

## Tool calling

Registered `ellmer::tool()` definitions work with the normal ellmer Chat API.
`chat_codex()` sends the definitions using the Codex Responses function-call
protocol, executes each returned call locally, sends the result back, and
continues until Codex produces its final response:

```r
weather_tool <- ellmer::tool(
  function(city) paste("Sunny in", city),
  name = "get_weather",
  description = "Get the current weather for a city.",
  arguments = list(city = ellmer::type_string())
)

chat <- chat_codex()
chat$register_tool(weather_tool)
chat$chat("What is the weather in Montevideo?")
```

The loop supports multiple and sequential calls, fragmented streaming
arguments, tool errors and `ellmer::tool_reject()`, calls with no preceding
assistant text, and streamed content through `$stream(stream = "content")`.
Tool requests and results remain `ellmer::ContentToolRequest` and
`ellmer::ContentToolResult` objects in the conversation history. Cloning,
callbacks, dangling tool requests, cancellation, sync/async tool execution,
and multiple tool rounds remain ellmer Chat behavior.

Image and PDF content uses ellmer's normal constructors and is serialized as
Codex Responses input. Terminal image content is retained when the adapter
repairs streamed text, so multimodal turns do not collapse to text-only
history:

```r
chat$chat(
  ellmer::content_image_url("https://example.com/diagram.png"),
  ellmer::ContentPDF("application/pdf", "<base64-data>", "report.pdf"),
  "Explain these files."
)
```

Response content is normalized in event order. Text, tool requests, images,
PDFs, reasoning, terminal/provider items, usage, duration, finish metadata,
and structured content remain attached to the ellmer assistant turn. Unknown
Responses items are retained as `ContentJson` rather than discarded.

## Choose a model

Model availability depends on your account and workspace. Once authenticated,
the Codex catalog can be queried directly:

```r
models <- codex_models()
models[c("id", "display_name", "default_reasoning_effort",
         "supported_reasoning_efforts")]
```

`codex_models()` uses the package's verified catalog compatibility value by
default. Set `ELLMERCODEX_CLIENT_VERSION` only when the service requires a
different explicit compatibility value. With `model = NULL`, `chat_codex()`
selects the lowest-priority usable model returned by this account catalog and
fails with an actionable error if discovery is empty or unavailable.

Select a model explicitly when needed:

```r
chat <- chat_codex(model = models$id[[1]])
```

You can also set `ELLMERCODEX_MODEL` as an explicit model override and omit the
`model` argument:

```r
Sys.setenv(ELLMERCODEX_MODEL = models$id[[1]])
chat <- chat_codex()
```

Reasoning effort uses ellmer's `reasoning_effort` parameter and is forwarded
unchanged as Codex Responses `reasoning.effort`. The selected model's current
catalog row is validated before a chat is constructed:

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
subscription transport, converted to ellmer `ContentJson`, and then passed
through ellmer's normal schema conversion:

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

As in ellmer, `$chat_structured()` intentionally disables registered tools for
that request. Use `$chat()` first to gather tool-assisted context, then call
`$chat_structured()` to extract structured data from the conversation.

## Async chat and cancellation

The returned chat supports ellmer's asynchronous methods. `$chat_async()`
returns a promise, while `$stream_async()` returns an async generator of
promises. Tool-aware async calls accept `tool_mode = "sequential"` or
`"concurrent"` and preserve the registered tool callbacks:

```r
chat$chat_async("Summarize the conversation.")

controller <- ellmer::stream_controller()
stream <- chat$stream_async(
  "Write a short story.",
  stream = "content",
  controller = controller
)
# Pass `stream` to an async consumer such as a Shiny chat component.
# Call `controller$cancel()` from the UI to stop generation.
```

## Stable core compatibility scope

The returned object is the complete public ellmer 0.4.2 `Chat` surface:
`initialize`, `get_turns`, `set_turns`, `add_turn`, `get_system_prompt`,
`get_model`, `set_model`, `set_system_prompt`, `get_tokens`, `get_cost`,
`last_turn`, `chat`, `chat_structured`, `chat_structured_async`, `chat_async`,
`stream`, `stream_async`, `register_tool`, `register_tools`, `get_provider`,
`get_tools`, `set_tools`, `on_tool_request`, `on_tool_result`, and `clone`.
See [`docs/ellmer-chat-interface.md`](docs/ellmer-chat-interface.md) for the
derived signatures, state transitions, return shapes, and conversion rules.

`parallel_chat*()` and `batch_chat*()` are outside the stable core contract.
They are audited but explicitly unsupported: parallel helpers fail with
`codex_ellmer_parallel_batch_blocker`, while batch helpers fail through
ellmer's generic unsupported-provider check. Both stop before sending a request
and the batch path does not create a state file. The package does not claim
compatibility with those helpers.

The Codex endpoint and its Responses event names are undocumented compatibility
surfaces, so upstream protocol changes may require a package update. This is an
external transport caveat on an otherwise stable, version-pinned core Chat
contract; it is not a claim of OpenAI support or a guarantee that the observed
backend will remain available.

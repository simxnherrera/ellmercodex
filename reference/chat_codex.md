# Create a Codex chat backed by ellmer

`chat_codex()` returns a normal ellmer `Chat` object configured for the
public Responses API with ChatGPT plan usage. It does not start browser
authentication. Call
[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
explicitly first when no stored credential is available; an existing
credential is loaded and refreshed as needed.

## Usage

``` r
chat_codex(
  system_prompt = NULL,
  model = NULL,
  echo = c("none", "output", "all"),
  effort = NULL,
  params = NULL,
  api_args = list()
)
```

## Arguments

- system_prompt:

  Optional system prompt passed to ellmer.

- model:

  Optional Codex model name. If omitted, `chat_codex()` queries the
  authenticated account catalog and chooses its lowest-priority usable
  model. Set `ELLMERCODEX_MODEL` for an explicit environment override;
  model availability remains account- and workspace-specific. If
  discovery is empty or unavailable, construction fails with an
  actionable error.

- echo:

  One of `"none"`, `"output"`, or `"all"`; controls whether `$chat()`
  prints the completed text. The compatibility wrapper accepts `TRUE`,
  `FALSE`, and `"text"` as aliases for `"output"`, `"none"`, and
  `"output"`, respectively.

- effort:

  Optional Codex reasoning effort. It is forwarded through ellmer's
  `reasoning_effort` parameter. When the selected model appears in
  [`codex_models()`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md),
  the value must be one of its advertised efforts. For an explicit model
  absent from that catalog, the service validates the model and value.

- params:

  Optional ellmer model parameters, usually created with
  [`ellmer::params()`](https://ellmer.tidyverse.org/reference/params.html).
  A supplied `reasoning_effort` must agree with `effort`, when both are
  provided. Other ellmer-supported model parameters are passed through
  unchanged, except those ChatGPT plan usage rejects (for example
  `temperature`, `top_p`, and `max_tokens`), which fail before a request
  is sent.

- api_args:

  Optional named list of additional Responses arguments passed through
  ellmer on every request. This is an advanced escape hatch for
  Responses arguments accepted with ChatGPT plan usage. Arguments the
  documentation prohibits (such as `metadata`, `truncation`, or
  `previous_response_id`) fail before a request is sent; other
  unsupported arguments may be rejected by the remote service.

## Value

An object inheriting from ellmer's `Chat` class. The returned object
retains ellmer's public Chat methods, history, callbacks, registered
tools, asynchronous methods, and R6 cloning behavior.

## Details

The returned chat is the public `ellmer` `Chat` object (0.5.0 or later)
for interactive, single-conversation operations, including ordinary and
structured chat, synchronous and asynchronous streaming, tool
declarations and multi-round execution, callbacks, cancellation,
cloning, history, echo, model/provider configuration, rich content, and
response metadata. Provider token counting and file management are
unavailable with ChatGPT plan usage and fail before making a request.
The compatibility layer uses one contract-checked
provider/turn-submission seam while leaving public Chat methods and
ellmer lifecycle semantics intact. The separate ellmer parallel/batch
helpers are outside this stable core contract. Parallel helpers use the
package blocker, while batch helpers stop in ellmer's generic
unsupported-provider check because the Codex endpoint is stream-only.

`$chat_structured()` intentionally follows ellmer's semantics and
disables registered tools for that request. Call `$chat()` first when
tool-assisted context is needed, then use `$chat_structured()` to
extract structured data.

## Conditions

Invalid arguments signal `codex_chat_argument_error`. Missing or
incompatible ellmer installations signal `codex_ellmer_missing` or
`codex_ellmer_compatibility_error`. Authentication failures found before
the Chat is constructed retain their package condition classes.
Transport and protocol errors retain their specific Codex/ellmer
condition classes; compatibility-shape failures use
`codex_ellmer_compatibility_error`.

## Side effects

Constructing a chat reads the current process credential or this
package's credential store and may refresh an expired stored credential.
When `model` is omitted, or when an effort is supplied, it also queries
the authenticated account catalog. It does not open a browser or
generate a response.

## See also

[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md),
[`codex_account()`](https://simxnherrera.github.io/ellmercodex/reference/codex_account.md),
[`codex_models()`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md),
[`codex_logout()`](https://simxnherrera.github.io/ellmercodex/reference/codex_logout.md),
and
[`ellmer::chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html)

## Examples

``` r
if (FALSE) { # interactive()
chat <- chat_codex(
  system_prompt = "Be concise."
)
chat$chat("Hello")

weather_tool <- ellmer::tool(
  function(city) paste("Sunny in", city),
  name = "get_weather",
  description = "Get the current weather for a city.",
  arguments = list(city = ellmer::type_string())
)
chat$register_tool(weather_tool)
chat$chat("What is the weather in Montevideo?")
}
```

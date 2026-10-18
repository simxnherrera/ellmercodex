# ellmercodex

> **Documentación en español:**
> [Introducción](https://simxnherrera.github.io/ellmercodex/articles/ellmercodex-es.html)
> y [Primeros
> pasos](https://simxnherrera.github.io/ellmercodex/articles/getting-started-es.html),
> o, después de instalar el paquete,
> [`vignette("ellmercodex-es", package = "ellmercodex")`](https://simxnherrera.github.io/ellmercodex/articles/ellmercodex-es.md).

`ellmercodex` lets you use your ChatGPT plan from R through an
[`ellmer`](https://ellmer.tidyverse.org/) chat interface: the models in
your plan work as one more `ellmer` provider, with no API key. That
makes it easy to bring language models into your R analysis workflows.

The package is independent of OpenAI and does not require an API key or
the Codex CLI. It uses OpenAI’s documented [“Sign in with
ChatGPT”](https://developers.openai.com/siwc/token-sharing-open-source)
flow for open-source, locally hosted apps and the public Responses API.

The structured-output and tool examples are inspired by the [blog post
about `ellmercodex`](https://simxnherrera.github.io/blog/ellmercodex/).

## Installation

Install the released version from CRAN:

``` r

install.packages("ellmercodex")
```

Or the development version from GitHub with
[`pak`](https://pak.r-lib.org/):

``` r

install.packages("pak")
pak::pak("simxnherrera/ellmercodex")
```

If you are upgrading from 0.1.x, sign in again with
[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md):
the authentication flow changed and earlier credentials are not kept.

## Quick start

Check the local integration, sign in, and create a chat:

``` r

library(ellmercodex)

codex_available()
auth <- codex_login()

chat <- chat_codex(model = "gpt-6-luna", effort = "low")
chat$chat("Hello from R")
#> Hello! What are you working on in R?
```

[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
opens a browser window where you sign in with your ChatGPT account.
Because
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
returns an `ellmer` `Chat` object, most of the usual `ellmer` interface
works: each `$chat()` call keeps the conversation history, and
`$stream()` streams the response:

``` r

chat$stream("Give me three ideas for naming an R package.")
```

Once you have signed in, later sessions can call
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
directly. With `model = NULL`, the package picks a usable model from
your account’s catalog.

## More than a chatbot

Because you are working with an `ellmer` `Chat`, you can ask for
structured results instead of free text. For example, you can classify
an excerpt from a Uruguayan parliamentary debate on cannabis regulation:

``` r

# A real excerpt from a parliamentary debate on cannabis regulation
excerpt <- paste(
  "seguimos pensando que además de la represión y del combate al",
  "narcotráfico que debe seguir con firmeza y decisión como sociedad",
  "debemos apostar a dos o tres pilares fundamentales la educación",
  "la prevención y la rehabilitación"
)

result <- chat$chat_structured(
  paste(
    "Classify the excerpt as PREVENTIVE, PUNITIVE, MIXED, or NO_CLEAR_STANCE.",
    "Use MIXED when it argues for preventive and punitive responses at the",
    "same time. Answer in English.",
    "\n\nExcerpt:",
    excerpt
  ),
  type = ellmer::type_object(
    stance = ellmer::type_enum(c(
      "PREVENTIVE",
      "PUNITIVE",
      "MIXED",
      "NO_CLEAR_STANCE"
    )),
    rationale = ellmer::type_string()
  )
)

result
#> $stance
#> [1] "MIXED"
#>
#> $rationale
#> [1] "The excerpt supports firm repression and combating drug trafficking,
#> alongside education, prevention, and rehabilitation."
```

For text analysis, this gives you a structure that R can put into a
`data.frame`, validate, or analyze.

## An agent inside R

You can also register R functions as tools that the model may decide to
call during a conversation. Suppose you have already classified some
speeches:

``` r

speeches <- data.frame(
  party = c("FA", "FA", "PN", "PN", "PN"),
  stance = c("PREVENTIVE", "MIXED", "PUNITIVE", "PUNITIVE", "MIXED")
)
```

Write an R function that summarizes one party’s stances and expose it to
the model as an `ellmer` tool:

``` r

summarize_party <- function(party_name) {
  speeches |>
    dplyr::filter(party == party_name) |>
    dplyr::count(stance) |>
    jsonlite::toJSON()
}

summary_tool <- ellmer::tool(
  summarize_party,
  name = "summarize_party",
  description = "Count the policy stances in a party's speeches.",
  arguments = list(party_name = ellmer::type_string())
)

chat$register_tool(summary_tool)

chat$chat("Compare the policy stances of FA and PN. Use the available tool.")
#> FA has one **MIXED** stance and one **PREVENTIVE** stance. PN has one
#> **MIXED** stance and two **PUNITIVE** stances. Both have a mixed stance,
#> while FA's other stance is preventive and PN's are punitive.
```

The model can call `summarize_party()` for each party, receive the
results computed by R, and use them in its answer. A tool could just as
well query a database, search a corpus, run a calculation, or call an
API.

R still runs the functions: the model can only use the tools you
register explicitly, and it decides when to call them and with which
arguments. Structured requests do not use registered tools, as in
`ellmer`; gather tool-assisted context with `$chat()` first, then
extract the result with `$chat_structured()`.

## Choose a model

Model availability depends on your account and workspace. Query the
catalog after signing in:

``` r

models <- codex_models()
models[c("id", "display_name", "default_reasoning_effort",
         "supported_reasoning_efforts")]
```

The catalog does not always include every model the service accepts. You
can pass a model ID explicitly even when it is absent from
[`codex_models()`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md),
and the service validates the model and reasoning effort. For example,
`gpt-6-luna` works although the catalog does not list it.

Reasoning effort can be supplied directly or through `ellmer`
parameters:

``` r

chat <- chat_codex(model = "gpt-6-luna", effort = "max")

chat <- chat_codex(
  model = "gpt-6-luna",
  params = ellmer::params(reasoning_effort = "max")
)
```

Set `ELLMERCODEX_MODEL` to use a model without passing `model` each
time:

``` r

Sys.setenv(ELLMERCODEX_MODEL = "gpt-6-luna")
chat <- chat_codex()
```

## Async chat, cancellation, and files

The returned chat also supports `ellmer`’s asynchronous methods:

``` r

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

Images and PDFs work with `ellmer`’s usual content helpers:

``` r

chat$chat(
  ellmer::content_image_file("plot.png"),
  ellmer::content_pdf_file("report.pdf"),
  "Explain these files."
)
```

## Authentication

[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
opens the browser so you can choose your ChatGPT account and workspace
and allow ChatGPT plan usage. The first sign-in creates a registration
bound to that account; later sign-ins reuse it. The credential is stored
in `tools::R_user_dir("ellmercodex", "config")` (or `ELLMERCODEX_HOME`)
with owner-only permissions.

Inspect sign-in state with a redacted account summary:

``` r

codex_account()
```

For a session that lasts only as long as the R process:

``` r

auth <- codex_login(persist = FALSE)
```

[`codex_logout()`](https://simxnherrera.github.io/ellmercodex/reference/codex_logout.md)
signs out, revokes the token, and removes the credential stored by this
package. To switch accounts or workspaces, sign out and call
[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
again.

## Limitations

ChatGPT plan usage through “Sign in with ChatGPT” is an OpenAI preview:
it needs an eligible plan and workspace, and its limits and features may
change. During the preview, `temperature`, `top_p`, `max_tokens`, and
other arguments OpenAI excludes are not accepted; the package rejects
them before sending a request.

The supported scope is interactive, single-conversation use of the
public `ellmer` `Chat` object (`ellmer` 0.5.0 or later). Provider token
counting, file management, and the separate `parallel_chat*()` and
`batch_chat*()` helpers are not supported.

`ellmercodex` is an independent integration and is not affiliated with
or endorsed by OpenAI.

## Learn more

- The [getting-started
  vignette](https://cran.r-project.org/web/packages/ellmercodex/vignettes/getting-started.html)
  walks through authentication, chats, tools, structured output, and
  error handling. It is also available [in
  Spanish](https://simxnherrera.github.io/ellmercodex/articles/getting-started-es.html).
- The [technical
  design](https://github.com/simxnherrera/ellmercodex/blob/main/docs/technical-design.md)
  documents the architecture, credential lifecycle, transport boundary,
  error taxonomy, and release risks.
- The [`ellmer` compatibility
  inventory](https://github.com/simxnherrera/ellmercodex/blob/main/docs/ellmer-chat-interface.md)
  records the supported `Chat` methods, signatures, return values, and
  state transitions.
- **Experimental:** for persistent credentials in your own app on your
  own VM, see the [single-process Linux VM
  guide](https://github.com/simxnherrera/ellmercodex/blob/main/docs/hosted-oauth.md).
  Apps that serve other people need OpenAI’s approval first.
- In R, see
  [`?chat_codex`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md),
  [`?codex_login`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md),
  [`?codex_models`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md),
  and `?ellmercodex-conditions` for the function reference.

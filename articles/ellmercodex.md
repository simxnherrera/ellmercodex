# Getting started with ellmercodex

> *Versión en español:*
> [`vignette("ellmercodex-es", package = "ellmercodex")`](https://simxnherrera.github.io/ellmercodex/articles/ellmercodex-es.md).

`ellmercodex` lets you use your ChatGPT plan from R as an
[`ellmer`](https://ellmer.tidyverse.org/) provider. You sign in once
with your ChatGPT account, and
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
gives you an ordinary `ellmer` `Chat` object: no API key, and no Codex
CLI.

It uses OpenAI’s documented [“Sign in with
ChatGPT”](https://developers.openai.com/siwc/token-sharing-open-source)
flow for open-source, locally hosted apps, and the public Responses API.
ChatGPT plan usage is an OpenAI preview, and `ellmercodex` is not
affiliated with or endorsed by OpenAI.

The examples in this article need a signed-in session, so they are not
run when the article is built. The output shown comes from a real
session.

## Check your setup

``` r

library(ellmercodex)

codex_available()
#> [1] TRUE
```

[`codex_available()`](https://simxnherrera.github.io/ellmercodex/reference/codex_available.md)
checks that the installed dependencies and the supported `ellmer`
version are in place. It does not read your credentials or contact the
network, so `TRUE` does not guarantee that a request will succeed.

## Sign in

``` r

codex_login()
```

[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
opens your browser, where you choose a ChatGPT account and workspace and
allow ChatGPT plan usage. The credential is saved privately and
refreshed automatically, so you only need to do this once per machine.
[`vignette("authentication")`](https://simxnherrera.github.io/ellmercodex/articles/authentication.md)
covers where it is stored and how to sign out or switch accounts.

## Your first chat

``` r

chat <- chat_codex(model = "gpt-6-luna", effort = "low")
chat$chat("Hello from R")
#> Hello! What are you working on in R?
```

Each `$chat()` call adds to the conversation history, so follow-up
questions have the earlier context. Use `$stream()` to see the answer as
it is generated:

``` r

chat$stream("Give me three ideas for naming an R package.")
```

If you leave out `model`,
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
picks a usable model from your account’s catalog.
[`vignette("models")`](https://simxnherrera.github.io/ellmercodex/articles/models.md)
explains how to list models, pick one, and set the reasoning effort.

## It is an ellmer Chat

[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
returns a regular `ellmer` `Chat`, so the `ellmer` documentation
applies. These work as they do with any other provider:

- **Structured data** with `$chat_structured()`: see `ellmer`’s
  [structured
  data](https://ellmer.tidyverse.org/articles/structured-data.html)
  article.
- **Tool calling** with `$register_tool()`: see [tool/function
  calling](https://ellmer.tidyverse.org/articles/tool-calling.html).
- **Streaming and async** with `$stream()`, `$chat_async()`, and
  `$stream_async()`, including cancellation with
  [`ellmer::stream_controller()`](https://ellmer.tidyverse.org/reference/stream_controller.html):
  see [streaming and async
  APIs](https://ellmer.tidyverse.org/articles/streaming-async.html).
- **Images and PDFs** with
  [`ellmer::content_image_file()`](https://ellmer.tidyverse.org/reference/content_image_url.html),
  [`ellmer::content_pdf_file()`](https://ellmer.tidyverse.org/reference/content_pdf_file.html),
  and friends.
- **Cloning and history** with `$clone()`, `$get_turns()`, and
  `$set_turns()`: see [programming with
  ellmer](https://ellmer.tidyverse.org/articles/programming.html).

[`vignette("text-analysis")`](https://simxnherrera.github.io/ellmercodex/articles/text-analysis.md)
puts structured data and tools together on a real text-analysis task.

A few things are different because of how ChatGPT plan usage works:
`parallel_chat()` and `batch_chat()` are not supported, and arguments
such as `temperature` and `max_tokens` are rejected.
[`vignette("errors-and-limits")`](https://simxnherrera.github.io/ellmercodex/articles/errors-and-limits.md)
lists them and shows how to handle errors.

## Learn more

- [`vignette("authentication")`](https://simxnherrera.github.io/ellmercodex/articles/authentication.md):
  signing in, stored credentials, and signing out.
- [`vignette("models")`](https://simxnherrera.github.io/ellmercodex/articles/models.md):
  models and reasoning effort.
- [`vignette("text-analysis")`](https://simxnherrera.github.io/ellmercodex/articles/text-analysis.md):
  structured data and tools on real text.
- [`vignette("errors-and-limits")`](https://simxnherrera.github.io/ellmercodex/articles/errors-and-limits.md):
  condition classes, plan limits, and what is not supported.

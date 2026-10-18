# Models and reasoning effort

> *Versión en español:*
> [`vignette("models-es", package = "ellmercodex")`](https://simxnherrera.github.io/ellmercodex/articles/models-es.md).

``` r

library(ellmercodex)
```

Which models you can use depends on your ChatGPT plan, account, and
workspace. This article shows how to find out what is available, pick a
model, and set how much the model reasons before it answers.

## List the models for your account

After signing in,
[`codex_models()`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md)
returns the models listed for your account:

``` r

models <- codex_models()
models[c("id", "display_name", "default_reasoning_effort",
         "supported_reasoning_efforts")]
```

It queries `https://api.openai.com/v1/models` with your ChatGPT plan
token and keeps the models marked `visibility: "list"`.

The catalog does not always include every model the service accepts. You
can pass a model ID even when it is missing from
[`codex_models()`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md);
the service then validates the model and reasoning effort. For example,
`gpt-6-luna` works although the catalog does not list it.

## Pick a model

With no `model`,
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
picks a usable model from the catalog. That is convenient interactively,
but the choice can change over time. Pass a model explicitly when you
need stable results:

``` r

chat <- chat_codex(model = "gpt-6-luna")
```

To use the same model everywhere without passing it each time, set
`ELLMERCODEX_MODEL`, for example in your `.Renviron`:

``` r

Sys.setenv(ELLMERCODEX_MODEL = "gpt-6-luna")
chat <- chat_codex()
```

## Set the reasoning effort

Reasoning models can spend more or less effort before answering. More
effort usually gives better answers to hard questions, but it is slower
and uses more of your plan. Set it with `effort`:

``` r

chat <- chat_codex(model = "gpt-6-luna", effort = "low")
```

or with `ellmer`’s parameters, which is handy if your code already uses
[`ellmer::params()`](https://ellmer.tidyverse.org/reference/params.html)
with other providers:

``` r

chat <- chat_codex(
  model = "gpt-6-luna",
  params = ellmer::params(reasoning_effort = "max")
)
```

The levels a model supports are in the `supported_reasoning_efforts`
column of
[`codex_models()`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md).
For models that are not in the catalog, the service validates the effort
when you send a request.

# List models available to the authenticated Codex account.

This makes one authenticated request to OpenAI's documented model
catalog (`GET https://api.openai.com/v1/models`) with the ChatGPT plan
access token, and keeps the models marked for listing
(`visibility: "list"`). The returned rows include each model's
advertised reasoning effort levels, so callers can select an effort
without copying a stale catalog into this package. Availability is
account- and workspace-specific. The catalog may lag behind models
accepted by the chat service; explicitly supplied IDs absent from the
catalog are passed to the service for validation.

## Usage

``` r
codex_models(auth = NULL, client_version = NULL)
```

## Arguments

- auth:

  Optional package credential. If omitted, the current session or
  package-owned credential is loaded and refreshed as needed.

- client_version:

  Deprecated and ignored. The documented catalog does not take a client
  version. Kept so existing calls keep working.

## Value

A `codex_models` data frame with one row per catalog model. Its columns
are:

- `id`:

  The model identifier accepted by
  [chat_codex](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md).

- `owned_by`:

  The service or owner label advertised by the catalog.

- `display_name`:

  A human-readable model name.

- `description`:

  The catalog description, when supplied.

- `default_reasoning_effort`:

  The advertised default effort.

- `supported_reasoning_efforts`:

  A list-column of effort names.

- `supported_in_api`:

  Whether the catalog marks the model as API-supported.

- `priority`:

  The catalog priority, when supplied.

- `default_service_tier`:

  The advertised default service tier.

- `service_tiers`:

  A list-column of advertised service tiers.

The `supported` and `source` attributes describe the catalog result.

## Note

The catalog is account- and workspace-specific and is queried at call
time. Cache or select a model explicitly if a reproducible workflow must
not change when the account's catalog changes.

## Conditions

Missing credentials signal `codex_auth_missing`; HTTP and protocol
failures use the same sanitized transport conditions as generation
requests.

## Examples

``` r
if (FALSE) { # interactive()
models <- codex_models()
models[c("id", "default_reasoning_effort", "supported_reasoning_efforts")]
}
```

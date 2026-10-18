# Show a redacted Codex authentication summary.

The account identifier and all token material are deliberately replaced
or omitted. Calling this function does not open a browser; an expired
stored credential may be refreshed.

## Usage

``` r
codex_account(auth = NULL)
```

## Arguments

- auth:

  Optional in-memory credential. If omitted, the current process-local
  session and then the package's own credential store are checked.

## Value

A one-row data frame with columns:

- `authenticated`:

  Logical; whether a valid package credential was found.

- `account`:

  Always `"<redacted>"`; account identifiers are never returned.

- `expires_at`:

  The access-token expiry as a UTC `POSIXct` value, or `NA` when
  unauthenticated.

## Conditions

A malformed in-memory credential signals `codex_auth_argument_error` and
a malformed stored value signals `codex_credential_store_error`.

## Examples

``` r
if (FALSE) { # interactive()
codex_account()
}
```

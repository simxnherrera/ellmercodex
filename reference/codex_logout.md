# Sign out and remove ellmercodex's stored credential.

This function revokes the refresh token with OpenAI (by default), clears
the process-local session, and deletes this package's own credential
file. It never removes Codex CLI credentials or another application's
entries. The host identifier is kept because the documented flow
requires it to stay stable for this host.

## Usage

``` r
codex_logout(revoke = TRUE)
```

## Arguments

- revoke:

  Whether to revoke the refresh token at OpenAI's documented revocation
  endpoint before deleting it locally. Revocation is best effort: local
  credentials are removed even when the network request fails, in which
  case a `codex_revocation_warning` warning is signaled.

## Value

`TRUE`, invisibly. The process-local credential is cleared even if no
persistent credential exists.

## Note

To use a different ChatGPT account or workspace, call `codex_logout()`
and then
[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md);
the next sign-in creates a new registration instead of reauthorizing the
previous one.

## Conditions

Logout signals no backend details. Storage failures are reported as
`codex_credential_store_error` by the explicit login and refresh paths
that write credentials.

## Examples

``` r
if (FALSE) { # interactive()
codex_logout()
}
```

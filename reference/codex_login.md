# Sign in with ChatGPT in the browser.

`codex_login()` is the explicit authentication entry point. It follows
OpenAI's documented "Sign in with ChatGPT" flow for open-source, locally
hosted apps: it opens the system browser for registration and consent,
listens once on the loopback callback, exchanges the PKCE-protected code
for tokens with the issued client ID, verifies the ID token, and checks
that ChatGPT plan usage (`chatgpt.tokens.use.direct`) was granted.

## Usage

``` r
codex_login(persist = TRUE, timeout = 300)
```

## Arguments

- persist:

  Whether to save the credential for later sessions. The default is
  `TRUE`; the credential is written to this package's own directory (see
  Details) with owner-only permissions. Use `FALSE` for a process-only
  session.

- timeout:

  Maximum callback wait in seconds. This must be one positive number.
  The loopback listener is closed when authentication succeeds, fails,
  or times out. When `persist = FALSE`, the credential remains available
  to
  [`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
  only in the current R process.

## Value

An internal `codex_auth` object. Use
[`codex_account()`](https://simxnherrera.github.io/ellmercodex/reference/codex_account.md)
for a safe account summary; token fields are intentionally not printed.

## Details

The first sign-in creates a registration bound to the selected ChatGPT
account and workspace. Later sign-ins reauthorize that registration. Use
[`codex_logout()`](https://simxnherrera.github.io/ellmercodex/reference/codex_logout.md)
first to sign in with a different account or workspace. The package
never reads credentials created by Codex CLI or another application.

Credentials are stored in `tools::R_user_dir("ellmercodex", "config")`,
or in the directory named by the `ELLMERCODEX_HOME` environment
variable. The same directory holds a stable, opaque host identifier
(`ext_agent_host_id`) that is created before the first sign-in, even
when `persist = FALSE`, because the flow requires it to be stable for
each host.

## Note

This function is interactive: it opens the default browser and listens
on `http://127.0.0.1:1455/callback` (set `ELLMERCODEX_CALLBACK_PORT` to
use another port).

## Conditions

Invalid arguments signal `codex_auth_argument_error`; callback and token
failures use `codex_oauth_callback_error`, `codex_oauth_timeout`, or
`codex_token_exchange_error` as appropriate. If ChatGPT plan usage was
not granted, `codex_plan_scope_error` is signaled.

## Examples

``` r
if (FALSE) { # interactive()
auth <- codex_login()
codex_account(auth)
}
```

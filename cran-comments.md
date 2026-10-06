## R CMD check results

0 errors | 0 warnings | 1 note

* The local macOS check completed successfully, including package vignette
  generation and re-building of vignette outputs.
* The only NOTE from `R CMD check --as-cran` is the expected
  "New submission" incoming-feasibility note for a package not yet on CRAN.

## Test environments

* Local: macOS 27.0.1, arm64, R 4.6.1
* GitHub Actions: ubuntu-latest (R devel, release, oldrel-1; ellmer 0.5.0 and
  latest), windows-latest (R release), macos-latest (R release)

## External service behavior

The package uses OpenAI's documented "Sign in with ChatGPT" flow for
open-source, locally hosted apps
(<https://developers.openai.com/siwc/token-sharing-open-source>): OAuth with
dynamic client registration and PKCE, followed by the public Responses API at
`https://api.openai.com/v1`. It does not reuse another application's OAuth
client or call undocumented endpoints. Credentials are written only after the
user calls `codex_login()`, to `tools::R_user_dir("ellmercodex", "config")`
(or `ELLMERCODEX_HOME`), with owner-only permissions; `codex_logout()` revokes
and removes them. Tests point that directory at `tempdir()`.

The package connects to an external service only after an explicit user call.
Package loading, examples, vignettes, and automated tests are offline: they do
not start OAuth, open a browser, inspect a credential store, or make a network
request. Network and upstream-protocol failures are converted to informative,
sanitized package conditions. The package does not retry generation requests,
because the service may already have accepted a generation.

## Use of unexported 'ellmer' functions

'ellmer' documents (`?ellmer::Provider`) that new backends are added by
subclassing `Provider` and implementing its S7 generics, but those generics are
not exported. This package therefore registers its provider methods on
'ellmer' generics obtained with `utils::getFromNamespace()`.

With a ChatGPT plan token, OpenAI's Responses API only accepts streaming
requests (documented as a preview limitation), while 'ellmer' sends
non-streaming chat requests through an internal, non-generic code path. To
support it, the package replaces the private turn-submission methods of each
'ellmer' `Chat` object it creates; it never modifies 'ellmer''s namespace or
other packages' objects.

To keep this safe for 'ellmer' and CRAN:

* Before creating a chat, the package checks every private symbol and argument
  it relies on and fails with a classed, informative error if 'ellmer' has
  changed.
* On CRAN, tests that construct chats are skipped if that check fails, so a
  future 'ellmer' release cannot turn private-contract drift into a reverse
  dependency check failure. Local and CI runs still fail on drift.
* I have asked the 'ellmer' maintainers to export the provider generics and to
  support stream-only providers, which would remove this code entirely:
  <https://github.com/tidyverse/ellmer/issues/1173>

## Method references

There are no published references describing the methods in this package. It
implements a provider for the 'ellmer' chat interface.

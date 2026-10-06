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

The Codex endpoint only supports streaming responses, while 'ellmer' sends
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
  <ISSUE_URL>

## Method references

There are no published references describing the methods in this package. It
implements a provider for the 'ellmer' chat interface.

## R CMD check results

0 errors | 0 warnings | 1 note

* The local macOS check completed successfully, including package vignette
  generation and re-building of vignette outputs.
* The only NOTE from `R CMD check --as-cran` is the expected
  "New submission" incoming-feasibility note for a package not yet on CRAN.

## Test environments

* Local: macOS 26.5.2, arm64, R 4.6.1

## External service behavior

The package connects to an external service only after an explicit user call.
Package loading, examples, vignettes, and automated tests are offline: they do
not start OAuth, open a browser, inspect a credential store, or make a network
request. Network and upstream-protocol failures are converted to informative,
sanitized package conditions. The package does not retry generation requests.

## R CMD check results

0 errors | 0 warnings | 2 notes

* This is a new submission.
* The local macOS check skipped HTML validation because Apple's bundled
  `/usr/bin/tidy` is the 2006 release. Package HTML and vignette generation
  completed successfully; this is a limitation of the local system utility.

## Test environments

* Local: macOS 26.5.2, arm64, R 4.6.1

## External service behavior

The package connects to an external service only after an explicit user call.
Package loading, examples, vignettes, and automated tests are offline: they do
not start OAuth, open a browser, inspect a credential store, or make a network
request. Network and upstream-protocol failures are converted to informative,
sanitized package conditions. The package does not retry generation requests.

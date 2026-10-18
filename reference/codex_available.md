# Check whether the local ellmercodex integration is available.

This is an offline check. By default it verifies package dependencies
and static configuration only; it does not open a browser, make a
request, or inspect a credential store. Set `check_credentials = TRUE`
when an explicit credential-presence check is desired.

## Usage

``` r
codex_available(check_credentials = FALSE)
```

## Arguments

- check_credentials:

  Whether to inspect this package's own credential backend. Defaults to
  `FALSE` to keep ordinary availability checks free of credential-store
  I/O.

## Value

A single logical value. `TRUE` means that the required dependencies,
static configuration, and the supported `ellmer` compatibility seam are
available. With `check_credentials = TRUE`, it also requires a usable
package-owned credential to be present. `FALSE` does not identify a
single cause; use the package startup diagnostics or contact the package
maintainer with a sanitized reproducible report.

## Note

The default check does not prove that the remote Codex service is
reachable, that a model is available to the account, or that a request
will succeed.

## Examples

``` r
codex_available()
#> [1] TRUE
if (interactive()) codex_available(check_credentials = TRUE)
```

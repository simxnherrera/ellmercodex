testthat::test_that("availability diagnostics are offline and redacted", {
  diagnostics <- codex_diagnostics(check_credentials = FALSE)
  testthat::expect_true(is.list(diagnostics))
  testthat::expect_true(is.logical(diagnostics$available))
  testthat::expect_true(diagnostics$ellmer$compatible)
  testthat::expect_match(diagnostics$ellmer$version, "^0\\.4\\.")
  testthat::expect_false(diagnostics$authentication$checked)
  testthat::expect_identical(diagnostics$authentication$status, "not_checked")
  testthat::expect_true(diagnostics$model_discovery$supported)
  testthat::expect_true(diagnostics$model_discovery$endpoint_configured)
  testthat::expect_false(any(grepl("account|token|secret|code", names(diagnostics), ignore.case = TRUE)))
  testthat::expect_identical(ellmercodex::codex_available(), diagnostics$available)
})

testthat::test_that("optional credential diagnostics report status without content", {
  # Replace the credential loader so this branch remains a fully offline test.
  testthat::local_mocked_bindings(
    codex_credentials_load = function(required = TRUE) NULL,
    .package = "ellmercodex"
  )
  diagnostics <- codex_diagnostics(check_credentials = TRUE)
  testthat::expect_true(diagnostics$authentication$checked)
  testthat::expect_identical(diagnostics$authentication$status, "missing")
  testthat::expect_false(any(grepl("fixture-access|refresh|account-id", capture.output(str(diagnostics)))))
})

testthat::test_that("availability includes the supported ellmer seam", {
  testthat::local_mocked_bindings(
    codex_ellmer_compatibility = function() {
      rlang::abort("fixture incompatibility")
    },
    .package = "ellmercodex"
  )
  diagnostics <- codex_diagnostics(check_credentials = FALSE)
  testthat::expect_false(diagnostics$ellmer$compatible)
  testthat::expect_false(diagnostics$available)
  testthat::expect_false(ellmercodex::codex_available())
})

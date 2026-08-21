testthat::test_that("the public API remains deliberately small", {
  expected <- c(
    "chat_codex",
    "codex_account",
    "codex_available",
    "codex_login",
    "codex_logout",
    "codex_models"
  )
  testthat::expect_setequal(getNamespaceExports("ellmercodex"), expected)
})

testthat::test_that("package loading has no lifecycle side effects", {
  namespace <- asNamespace("ellmercodex")
  testthat::expect_false(exists(".onLoad", envir = namespace, inherits = FALSE))
  testthat::expect_false(exists(".onAttach", envir = namespace, inherits = FALSE))
})

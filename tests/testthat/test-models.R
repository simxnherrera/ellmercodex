testthat::test_that("model discovery returns an isolated unsupported result", {
  result <- ellmercodex::codex_models()
  testthat::expect_s3_class(result, "codex_models_unsupported")
  testthat::expect_true(is.data.frame(result))
  testthat::expect_false(attr(result, "supported"))
  testthat::expect_match(attr(result, "reason"), "not supported")
  testthat::expect_length(result$id, 0L)
  testthat::expect_length(result$owned_by, 0L)
})

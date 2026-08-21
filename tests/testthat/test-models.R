testthat::test_that("model discovery normalizes Codex model metadata", {
  seen <- new.env(parent = emptyenv())
  result <- httr2::with_mocked_responses(
    function(req) {
      seen$request <- req
      httr2::response_json(body = list(
        models = list(
          list(
            slug = "fixture-model",
            display_name = "Fixture Model",
            description = "A fixture model.",
            default_reasoning_level = "medium",
            supported_reasoning_levels = list(
              list(effort = "low", description = "Fast"),
              list(effort = "medium", description = "Balanced"),
              list(effort = "high", description = "Deep")
            ),
            supported_in_api = TRUE,
            priority = 1L,
            service_tiers = list(list(id = "default", name = "Default"))
          )
        )
      ))
    },
    ellmercodex::codex_models(
      auth = fake_codex_auth(),
      client_version = "fixture-client"
    )
  )

  testthat::expect_s3_class(result, "codex_models")
  testthat::expect_true(is.data.frame(result))
  testthat::expect_true(attr(result, "supported"))
  testthat::expect_identical(result$id, "fixture-model")
  testthat::expect_identical(result$display_name, "Fixture Model")
  testthat::expect_identical(result$default_reasoning_effort, "medium")
  testthat::expect_identical(
    result$supported_reasoning_efforts[[1L]],
    c("low", "medium", "high")
  )
  testthat::expect_identical(result$service_tiers[[1L]], "default")
  testthat::expect_match(seen$request$url, "/codex/models")
  testthat::expect_match(seen$request$url, "client_version=fixture-client")
  testthat::expect_identical(seen$request$headers$Accept, "application/json")
})

testthat::test_that("empty and malformed model catalogs fail safely", {
  empty <- ellmercodex:::codex_models_parse(list(models = list()))
  testthat::expect_s3_class(empty, "codex_models")
  testthat::expect_true(attr(empty, "supported"))
  testthat::expect_length(empty$id, 0L)

  testthat::expect_error(
    ellmercodex:::codex_models_parse(list(unexpected = TRUE)),
    class = "codex_protocol_changed_error"
  )
})

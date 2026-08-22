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
  testthat::expect_output(
    print(result[c("id", "display_name")]),
    "fixture-model"
  )
})

testthat::test_that("model discovery does not require the Codex executable", {
  old_path <- Sys.getenv("PATH", unset = NA_character_)
  old_version <- Sys.getenv("ELLMERCODEX_CLIENT_VERSION", unset = NA_character_)
  on.exit({
    if (is.na(old_path)) Sys.unsetenv("PATH") else Sys.setenv(PATH = old_path)
    if (is.na(old_version)) {
      Sys.unsetenv("ELLMERCODEX_CLIENT_VERSION")
    } else {
      Sys.setenv(ELLMERCODEX_CLIENT_VERSION = old_version)
    }
  }, add = TRUE)
  Sys.setenv(PATH = "")
  Sys.unsetenv("ELLMERCODEX_CLIENT_VERSION")

  seen <- new.env(parent = emptyenv())
  httr2::with_mocked_responses(
    function(req) {
      seen$request <- req
      httr2::response_json(body = list(models = list()))
    },
    ellmercodex::codex_models(auth = fake_codex_auth())
  )

  version <- codex_models_client_version()
  testthat::expect_identical(version, "0.149.0")
  testthat::expect_match(seen$request$url, paste0("client_version=", version))

  seen_without_version <- new.env(parent = emptyenv())
  httr2::with_mocked_responses(
    function(req) {
      seen_without_version$request <- req
      httr2::response_json(body = list(models = list()))
    },
    ellmercodex::codex_models(
      auth = fake_codex_auth(),
      client_version = NULL
    )
  )
  testthat::expect_match(
    seen_without_version$request$url,
    paste0("client_version=", version)
  )
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

testthat::test_that("chat default selection uses the account catalog", {
  old_model <- Sys.getenv("ELLMERCODEX_MODEL", unset = NA_character_)
  on.exit({
    if (is.na(old_model)) Sys.unsetenv("ELLMERCODEX_MODEL") else {
      Sys.setenv(ELLMERCODEX_MODEL = old_model)
    }
  }, add = TRUE)
  Sys.unsetenv("ELLMERCODEX_MODEL")

  testthat::local_mocked_bindings(
    codex_auth = function() fake_codex_auth(),
    .package = "ellmercodex"
  )
  chat <- httr2::with_mocked_responses(
    function(req) httr2::response_json(body = list(models = list(
      list(
        slug = "fixture-lower-priority",
        display_name = "Lower priority",
        supported_in_api = TRUE,
        priority = 20L
      ),
      list(
        slug = "fixture-default",
        display_name = "Fixture default",
        supported_in_api = TRUE,
        priority = 1L
      )
    ))),
    ellmercodex::chat_codex(echo = "none")
  )

  testthat::expect_identical(chat$get_model(), "fixture-default")
})

testthat::test_that("reasoning effort is validated against the selected model", {
  testthat::local_mocked_bindings(
    codex_auth = function() fake_codex_auth(),
    .package = "ellmercodex"
  )
  catalog_response <- function(req) httr2::response_json(body = list(models = list(
    list(
      slug = "fixture-model",
      display_name = "Fixture Model",
      supported_in_api = TRUE,
      priority = 1L,
      default_reasoning_level = "medium",
      supported_reasoning_levels = list(
        list(effort = "low"),
        list(effort = "medium"),
        list(effort = "high")
      )
    )
  )))

  chat <- httr2::with_mocked_responses(
    catalog_response,
    ellmercodex::chat_codex(
      model = "fixture-model",
      params = ellmer::params(reasoning_effort = "high"),
      echo = "none"
    )
  )
  testthat::expect_identical(
    chat$get_provider()@params$reasoning_effort,
    "high"
  )

  testthat::expect_error(
    httr2::with_mocked_responses(
      catalog_response,
      ellmercodex::chat_codex(
        model = "fixture-model",
        effort = "maximum",
        echo = "none"
      )
    ),
    class = "codex_model_selection_error",
    regexp = "Supported values: low, medium, high"
  )
  testthat::expect_error(
    ellmercodex::chat_codex(
      model = "fixture-model",
      effort = "low",
      params = ellmer::params(reasoning_effort = "high"),
      echo = "none"
    ),
    class = "codex_chat_argument_error",
    regexp = "must match"
  )
  testthat::expect_error(
    ellmercodex::chat_codex(
      model = "fixture-model",
      params = list(reasoning_effort = 1),
      echo = "none"
    ),
    class = "codex_chat_argument_error"
  )
})

testthat::test_that("default selection fails actionably when discovery is empty or unavailable", {
  testthat::local_mocked_bindings(
    codex_auth = function() fake_codex_auth(),
    .package = "ellmercodex"
  )

  empty_error <- testthat::expect_error(
    httr2::with_mocked_responses(
      function(req) httr2::response_json(body = list(models = list())),
      ellmercodex::chat_codex(echo = "none")
    ),
    class = "codex_model_selection_error"
  )
  testthat::expect_match(empty_error$message, "catalog is empty")
  testthat::expect_match(empty_error$message, "codex_models")

  unavailable_error <- testthat::expect_error(
    httr2::with_mocked_responses(
      function(req) stop("offline fixture network failure"),
      ellmercodex::chat_codex(echo = "none")
    ),
    class = "codex_model_selection_error"
  )
  testthat::expect_match(unavailable_error$message, "could not be discovered")
  testthat::expect_match(unavailable_error$message, "explicitly verified model")
})

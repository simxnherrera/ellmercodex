testthat::test_that("unstable endpoints and headers are centralized", {
  functions <- c(
    "codex_oauth_client_id", "codex_authorization_url", "codex_token_url",
    "codex_responses_url", "codex_protocol_version", "codex_callback_port",
    "codex_redirect_uri", "codex_originator", "codex_default_model",
    "codex_request_headers"
  )
  testthat::expect_true(all(vapply(
    functions,
    function(name) exists(name, envir = asNamespace("ellmercodex"), inherits = FALSE),
    logical(1)
  )))
  testthat::expect_match(codex_authorization_url(), "^https://")
  testthat::expect_match(codex_token_url(), "^https://")
  testthat::expect_match(codex_responses_url(), "^https://")
  testthat::expect_identical(codex_redirect_uri(), "http://localhost:1455/auth/callback")
  testthat::expect_identical(codex_originator(), "ellmercodex")
})

testthat::test_that("request body is streaming and does not store server-side state", {
  body <- codex_request_body("fixture prompt", model = "fixture-model")
  testthat::expect_identical(body$model, "fixture-model")
  testthat::expect_identical(body$stream, TRUE)
  testthat::expect_identical(body$store, FALSE)
  testthat::expect_identical(body$input[[1L]]$role, "user")
  testthat::expect_identical(body$input[[1L]]$content[[1L]]$type, "input_text")
  testthat::expect_identical(body$input[[1L]]$content[[1L]]$text, "fixture prompt")
  testthat::expect_null(body$reasoning)
  testthat::expect_error(
    codex_request_body(""),
    class = "codex_request_error"
  )
  testthat::expect_error(
    codex_request_body("fixture", model = ""),
    class = "codex_request_error"
  )
  effort_body <- codex_request_body(
    "fixture prompt",
    model = "fixture-model",
    effort = "high"
  )
  testthat::expect_identical(
    effort_body$reasoning,
    list(effort = "high", summary = "auto")
  )
  testthat::expect_error(
    codex_request_body("fixture", effort = ""),
    class = "codex_request_error"
  )
})

testthat::test_that("request headers contain only the required routing metadata", {
  headers <- codex_request_headers(fake_codex_auth())
  testthat::expect_identical(unname(headers[["ChatGPT-Account-Id"]]), "fixture-account-id")
  testthat::expect_identical(unname(headers[["originator"]]), "ellmercodex")
  testthat::expect_identical(unname(headers[["OpenAI-Beta"]]), "responses=experimental")
  testthat::expect_identical(unname(headers[["Accept"]]), "text/event-stream")
  testthat::expect_match(headers[["Authorization"]], "^Bearer fixture-access-token$")
  testthat::expect_error(
    codex_request_headers(list(access_token = "fixture")),
    class = "codex_authentication_error"
  )
})

testthat::test_that("HTTP errors are classified without exposing raw bodies", {
  response <- httr2::response_json(
    status_code = 401L,
    body = list(error = list(code = "invalid_token", message = "Bearer fixture-secret-token"))
  )
  error <- testthat::expect_error(
    codex_abort_response(response),
    class = "codex_authentication_error"
  )
  testthat::expect_s3_class(error, "codex_authentication_error")
  testthat::expect_false(grepl("fixture-secret-token", conditionMessage(error), fixed = TRUE))

  testthat::expect_error(
    codex_abort_response(httr2::response_json(429L, body = list(detail = "slow down"))),
    class = "codex_rate_limit_error"
  )
  testthat::expect_error(
    codex_abort_response(httr2::response_json(404L, body = list(detail = "not found"))),
    class = "codex_model_unavailable_error"
  )
  testthat::expect_error(
    codex_abort_response(httr2::response_json(422L, body = list(detail = "invalid request"))),
    class = "codex_malformed_request_error"
  )
  testthat::expect_error(
    codex_abort_response(httr2::response_json(503L, body = list(detail = "upstream"))),
    class = "codex_server_error"
  )
})

testthat::test_that("ordinary JSON response fallback assembles text", {
  value <- list(output = list(list(
    type = "message",
    content = list(list(type = "output_text", text = "fixture answer"))
  )))
  testthat::expect_identical(codex_parse_response(value), "fixture answer")
  testthat::expect_error(
    codex_parse_response(list(output = list())),
    class = "codex_protocol_changed_error"
  )
})

testthat::test_that("request construction can be exercised with a single mocked response", {
  seen <- new.env(parent = emptyenv())
  result <- httr2::with_mocked_responses(
    function(req) {
      seen$request <- req
      httr2::response_json(body = list(output = list(list(
        type = "message",
        content = list(list(type = "output_text", text = "mocked answer"))
      ))))
    },
    codex_generate("fixture prompt", auth = fake_codex_auth(), model = "fixture-model")
  )

  testthat::expect_identical(result, "mocked answer")
  testthat::expect_identical(seen$request$url, codex_responses_url())
  testthat::expect_identical(seen$request$body$data$model, "fixture-model")
  testthat::expect_identical(seen$request$body$data$stream, TRUE)
  testthat::expect_identical(seen$request$body$data$store, FALSE)
  testthat::expect_identical(seen$request$headers$originator, "ellmercodex")

  effort_result <- httr2::with_mocked_responses(
    function(req) {
      testthat::expect_identical(
        req$body$data$reasoning,
        list(effort = "high", summary = "auto")
      )
      httr2::response_json(body = list(output = list(list(
        type = "message",
        content = list(list(type = "output_text", text = "effort answer"))
      ))))
    },
    codex_generate(
      "fixture prompt",
      auth = fake_codex_auth(),
      model = "fixture-model",
      effort = "high"
    )
  )
  testthat::expect_identical(effort_result, "effort answer")
})

testthat::test_that("ordinary network failures are graceful and never retried", {
  calls <- 0L
  error <- httr2::with_mocked_responses(
    function(req) {
      calls <<- calls + 1L
      stop("Bearer fixture-secret-token")
    },
    testthat::expect_error(
      codex_generate("fixture prompt", auth = fake_codex_auth(), model = "fixture-model"),
      class = "codex_network_error"
    )
  )

  testthat::expect_identical(calls, 1L)
  testthat::expect_false(grepl("fixture-secret-token", conditionMessage(error), fixed = TRUE))
})

testthat::test_that("diagnostic detail is bounded and redacted", {
  detail <- paste(
    "Bearer very-secret",
    "access_token=very-secret",
    "https://example.invalid/path?code=secret",
    "person@example.invalid",
    strrep("x", 400),
    sep = " "
  )
  safe <- codex_sanitize_error_detail(detail)
  testthat::expect_lte(nchar(safe), 300L)
  testthat::expect_false(grepl("very-secret|person@example|https://", safe))
})

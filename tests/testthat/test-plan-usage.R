skip_if_ellmer_contract_changed()

plan_fixture_chat <- function(system_prompt = NULL, params = NULL, api_args = list()) {
  auth <- structure(
    list(access_token = "fixture-access-token", client_id = "oaiapp_fixtureclient"),
    class = c("codex_auth", "list")
  )
  codex_patch_chat(codex_ellmer_chat_openai(
    system_prompt = system_prompt,
    model = "fixture-model",
    auth = auth,
    params = params,
    api_args = api_args
  ))
}

test_that("bodies follow the ChatGPT plan usage restrictions", {
  body <- codex_responses_body_adapt(list(
    model = "fixture-model",
    input = list(
      list(role = "system", content = list(list(type = "input_text", text = "Be brief."))),
      list(role = "user", content = list(list(type = "input_text", text = "Hi"))),
      list(type = "function_call", call_id = "call_1", name = "get_weather", arguments = "{}")
    ),
    tools = list(
      list(type = "function", name = "get_weather", parameters = list(type = "object")),
      list(type = "web_search")
    ),
    store = TRUE,
    stream = FALSE
  ))
  expect_identical(body$input[[1L]]$role, "developer")
  expect_identical(body$input[[2L]]$role, "user")
  expect_identical(body$input[[3L]]$namespace, "ellmer")
  expect_identical(body$tools[[1L]]$type, "web_search")
  expect_identical(body$tools[[2L]]$type, "namespace")
  expect_identical(body$tools[[2L]]$name, "ellmer")
  expect_identical(body$tools[[2L]]$tools[[1L]]$name, "get_weather")
  expect_false(body$store)
  expect_true(body$stream)

  expect_null(codex_responses_body_adapt(list(input = list()))$tools)
  error <- expect_error(
    codex_responses_body_adapt(list(temperature = 0.2, max_output_tokens = 10L, user = "x")),
    class = "codex_chat_argument_error"
  )
  expect_match(conditionMessage(error), "max_output_tokens, temperature, user|temperature, max_output_tokens, user")
})

test_that("chat requests use the public Responses API with developer instructions", {
  chat <- plan_fixture_chat(system_prompt = "Answer briefly.")
  seen <- NULL
  answer <- httr2::with_mocked_responses(
    function(req) {
      seen <<- req
      fixture_stream_response("stream-async-empty-terminal.sse")
    },
    chat$chat("Hello")
  )
  expect_identical(seen$url, "https://api.openai.com/v1/responses")
  input <- seen$body$data$input
  expect_identical(input[[1L]]$role, "developer")
  expect_false(any(vapply(input, function(item) identical(item$role, "system"), logical(1))))
  expect_false(seen$body$data$store)
  expect_true(seen$body$data$stream)
  expect_null(seen$headers$`ChatGPT-Account-Id`)
  expect_null(seen$headers$`OpenAI-Beta`)
  expect_null(seen$headers$originator)
})

test_that("prohibited parameters fail before any request is sent", {
  chat <- plan_fixture_chat(params = ellmer::params(temperature = 0.3))
  calls <- 0L
  httr2::with_mocked_responses(
    function(req) {
      calls <<- calls + 1L
      fixture_stream_response("tool-no-text.sse")
    },
    expect_error(chat$chat("Hello"), class = "codex_chat_argument_error")
  )
  expect_identical(calls, 0L)

  chat <- plan_fixture_chat(api_args = list(previous_response_id = "resp_x"))
  expect_error(
    httr2::with_mocked_responses(function(req) stop("unexpected"), chat$chat("Hello")),
    class = "codex_chat_argument_error"
  )
})

test_that("only response.completed is a successful chat turn", {
  chat <- plan_fixture_chat()
  error <- expect_error(
    suppressWarnings(httr2::with_mocked_responses(
      function(req) fixture_stream_response("stream-incomplete.sse"),
      chat$chat("Hello")
    )),
    class = "codex_incomplete_error"
  )
  expect_match(conditionMessage(error), "max_output_tokens")
})

test_that("plan usage errors map to package conditions in chats", {
  chat <- plan_fixture_chat()
  error <- expect_error(
    httr2::with_mocked_responses(
      function(req) fixture_stream_response("stream-usage-limit.sse"),
      chat$chat("Hello")
    ),
    class = "codex_usage_limit_error"
  )
  expect_s3_class(error, "codex_rate_limit_error")

  chat <- plan_fixture_chat()
  error <- expect_error(
    httr2::with_mocked_responses(
      function(req) httr2::response_json(429L, body = list(error = list(
        code = "subscription_sharing_usage_limit_exceeded",
        message = "fixture usage limit"
      ))),
      chat$chat("Hello")
    ),
    class = "codex_usage_limit_error"
  )
  expect_s3_class(error, "codex_rate_limit_error")

  chat <- plan_fixture_chat()
  expect_error(
    httr2::with_mocked_responses(
      function(req) httr2::response_json(401L, body = list(detail = "Bearer fixture-secret")),
      chat$chat("Hello")
    ),
    class = "codex_authentication_error"
  )
})

test_that("SSE plan errors map to package conditions in the text transport", {
  expect_error(
    codex_parse_sse_response(codex_parse_sse(fixture_text("stream-usage-limit.sse"))),
    class = "codex_usage_limit_error"
  )
})

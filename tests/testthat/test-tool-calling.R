codex_ellmer_chat_openai <- getFromNamespace("codex_ellmer_chat_openai", "ellmercodex")
codex_patch_chat <- getFromNamespace("codex_patch_chat", "ellmercodex")

tool_fixture_response <- function(name) {
  fixture_stream_response(name)
}

new_tool_fixture_chat <- function() {
  auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  codex_patch_chat(codex_ellmer_chat_openai(model = "fixture-model", auth = auth))
}

test_that("a registered tool completes an end-to-end loop and preserves tool history", {
  skip_if_not_installed("ellmer")

  chat <- new_tool_fixture_chat()
  seen <- list()
  calls <- character()
  weather <- ellmer::tool(
    function(city) {
      calls <<- c(calls, city)
      paste0("Sunny in ", city)
    },
    name = "get_weather",
    description = "Get the current weather for a city.",
    arguments = list(city = ellmer::type_string())
  )
  chat$register_tools(list(weather))

  answer <- httr2::with_mocked_responses(
    function(req) {
      seen[[length(seen) + 1L]] <<- req
      if (length(seen) == 1L) {
        tool_fixture_response("tool-fragmented.sse")
      } else {
        tool_fixture_response("tool-final.sse")
      }
    },
    chat$chat("What is the weather in Montevideo?")
  )

  expect_identical(as.character(answer), "The weather result is sunny.")
  expect_identical(calls, "Montevideo")
  expect_length(seen, 2L)
  expect_length(seen[[1L]]$body$data$tools, 1L)
  expect_identical(seen[[1L]]$body$data$tools[[1L]]$name, "get_weather")

  second_input <- seen[[2L]]$body$data$input
  function_call <- second_input[[2L]]
  function_result <- second_input[[3L]]
  expect_identical(function_call$type, "function_call")
  expect_identical(function_call$call_id, "call_fragmented")
  expect_identical(function_result$type, "function_call_output")
  expect_identical(function_result$call_id, "call_fragmented")
  expect_identical(function_result$output, "Sunny in Montevideo")

  turns <- chat$get_turns()
  expect_length(turns, 4L)
  expect_true(inherits(turns[[2L]]@contents[[1L]], "ellmer::ContentToolRequest"))
  expect_identical(turns[[2L]]@contents[[1L]]@id, "call_fragmented")
  expect_true(inherits(turns[[3L]]@contents[[1L]], "ellmer::ContentToolResult"))
  expect_identical(turns[[3L]]@contents[[1L]]@request@id, "call_fragmented")
  expect_identical(turns[[4L]]@text, "The weather result is sunny.")
})

test_that("the chat_codex user-facing factory completes a registered tool loop", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  local_mocked_bindings(
    codex_auth = function() auth,
    codex_default_model = function() "fixture-model",
    .package = "ellmercodex"
  )

  chat <- ellmercodex::chat_codex(model = "fixture-model")
  tool <- ellmer::tool(
    function(city) paste0("Sunny in ", city),
    name = "get_weather",
    description = "Get weather.",
    arguments = list(city = ellmer::type_string())
  )
  chat$register_tool(tool)

  response_number <- 0L
  answer <- httr2::with_mocked_responses(
    function(req) {
      response_number <<- response_number + 1L
      tool_fixture_response(
        if (response_number == 1L) "tool-one.sse" else "tool-final.sse"
      )
    },
    chat$chat("What is the weather in Montevideo?")
  )

  expect_s3_class(answer, "ellmer_output")
  expect_identical(as.character(answer), "The weather result is sunny.")
  expect_identical(response_number, 2L)
})

test_that("multiple calls and sequential rounds execute in order", {
  skip_if_not_installed("ellmer")

  chat <- new_tool_fixture_chat()
  calls <- character()
  weather <- ellmer::tool(
    function(city) {
      calls <<- c(calls, city)
      paste0("weather-", city)
    },
    name = "get_weather",
    description = "Get weather.",
    arguments = list(city = ellmer::type_string())
  )
  chat$register_tool(weather)

  seen <- 0L
  request_bodies <- list()
  answer <- httr2::with_mocked_responses(
    function(req) {
      seen <<- seen + 1L
      request_bodies[[length(request_bodies) + 1L]] <<- req$body$data
      fixture <- switch(
        as.character(seen),
        `1` = "tool-multiple.sse",
        `2` = "tool-no-text.sse",
        "tool-final.sse"
      )
      tool_fixture_response(fixture)
    },
    chat$chat("Compare the weather, then check it again.")
  )

  expect_identical(as.character(answer), "The weather result is sunny.")
  expect_identical(calls, c("Montevideo", "Salto", "Montevideo"))
  expect_identical(seen, 3L)

  expect_true(any(vapply(
    request_bodies[[3L]]$input,
    function(item) is.list(item) && identical(item$type, "function_call_output"),
    logical(1)
  )))
})

test_that("tool errors and rejected tools become ContentToolResult errors", {
  skip_if_not_installed("ellmer")

  chat <- new_tool_fixture_chat()
  rejected <- ellmer::tool(
    function() ellmer::tool_reject("fixture rejection"),
    name = "fail_tool",
    description = "Always rejects.",
    arguments = list()
  )
  chat$register_tool(rejected)

  seen <- list()
  warning <- NULL
  answer <- withCallingHandlers(
    httr2::with_mocked_responses(
      function(req) {
        seen[[length(seen) + 1L]] <<- req
        if (length(seen) == 1L) {
          tool_fixture_response("tool-error.sse")
        } else {
          tool_fixture_response("tool-final.sse")
        }
      },
      chat$chat("Try the restricted tool.")
    ),
    warning = function(condition) {
      if (inherits(condition, "ellmer_tool_failure")) {
        warning <<- condition
        invokeRestart("muffleWarning")
      }
    }
  )

  expect_s3_class(warning, "ellmer_tool_failure")
  expect_identical(as.character(answer), "The weather result is sunny.")
  result <- chat$get_turns()[[3L]]@contents[[1L]]
  expect_true(inherits(result, "ellmer::ContentToolResult"))
  expect_true(inherits(result@error, "ellmer_tool_reject"))
  expect_match(seen[[2L]]$body$data$input[[3L]]$output, "fixture rejection")
})

test_that("ordinary tool exceptions are returned to Codex as tool errors", {
  skip_if_not_installed("ellmer")

  chat <- new_tool_fixture_chat()
  failing <- ellmer::tool(
    function() stop("fixture tool failure"),
    name = "fail_tool",
    description = "Always errors.",
    arguments = list()
  )
  chat$register_tool(failing)

  seen <- list()
  warning <- NULL
  answer <- withCallingHandlers(
    httr2::with_mocked_responses(
      function(req) {
        seen[[length(seen) + 1L]] <<- req
        if (length(seen) == 1L) {
          tool_fixture_response("tool-error.sse")
        } else {
          tool_fixture_response("tool-final.sse")
        }
      },
      chat$chat("Try the failing tool.")
    ),
    warning = function(condition) {
      if (inherits(condition, "ellmer_tool_failure")) {
        warning <<- condition
        invokeRestart("muffleWarning")
      }
    }
  )

  expect_s3_class(warning, "ellmer_tool_failure")
  expect_identical(as.character(answer), "The weather result is sunny.")
  expect_true(inherits(chat$get_turns()[[3L]]@contents[[1L]]@error, "condition"))
  expect_match(seen[[2L]]$body$data$input[[3L]]$output, "fixture tool failure")
})

test_that("ellmer tool-request callbacks can reject a call", {
  skip_if_not_installed("ellmer")

  chat <- new_tool_fixture_chat()
  invoked <- FALSE
  tool <- ellmer::tool(
    function() {
      invoked <<- TRUE
      "should not run"
    },
    name = "fail_tool",
    description = "A callback-rejected tool.",
    arguments = list()
  )
  chat$register_tool(tool)
  chat$on_tool_request(function(request) ellmer::tool_reject("callback rejection"))

  seen <- 0L
  answer <- withCallingHandlers(
    httr2::with_mocked_responses(
      function(req) {
        seen <<- seen + 1L
        tool_fixture_response(if (seen == 1L) "tool-error.sse" else "tool-final.sse")
      },
      chat$chat("Try the callback-rejected tool.")
    ),
    warning = function(condition) {
      if (inherits(condition, "ellmer_tool_failure")) invokeRestart("muffleWarning")
    }
  )

  expect_false(invoked)
  expect_identical(as.character(answer), "The weather result is sunny.")
  result <- chat$get_turns()[[3L]]@contents[[1L]]
  expect_match(as.character(result@error), "callback rejection")
})

test_that("content streaming yields text, tool request, result, and final text", {
  skip_if_not_installed("ellmer")

  chat <- new_tool_fixture_chat()
  weather <- ellmer::tool(
    function(city) paste0("Sunny in ", city),
    name = "get_weather",
    description = "Get weather.",
    arguments = list(city = ellmer::type_string())
  )
  chat$register_tool(weather)

  response_number <- 0L
  chunks <- httr2::with_mocked_responses(
    function(req) {
      response_number <<- response_number + 1L
      tool_fixture_response(if (response_number == 1L) "tool-no-text.sse" else "tool-final.sse")
    },
    coro::collect(chat$stream("Stream the weather.", stream = "content"))
  )

  expect_true(any(vapply(chunks, function(x) inherits(x, "ellmer::ContentToolRequest"), logical(1))))
  expect_true(any(vapply(chunks, function(x) inherits(x, "ellmer::ContentToolResult"), logical(1))))
  text <- paste0(vapply(chunks, fixture_chunk_text, character(1)), collapse = "")
  expect_identical(sub("\\n$", "", text), "The weather result is sunny.")
})

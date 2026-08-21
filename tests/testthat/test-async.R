test_that("async chat repairs Codex streamed text and terminal history", {
  skip_if_not_installed("ellmer")

  chat <- new_async_fixture_chat()
  outcome <- httr2::with_mocked_responses(
    function(req) fixture_stream_response("stream-async-empty-terminal.sse"),
    await_promise(chat$chat_async("Say hello."))
  )

  expect_null(outcome$error)
  expect_s3_class(outcome$value, "ellmer_output")
  expect_identical(as.character(outcome$value), "Hello async")
  expect_identical(chat$last_turn()@text, "Hello async")
})

test_that("async streaming preserves content chunks, callbacks, and tool modes", {
  skip_if_not_installed("ellmer")

  for (mode in c("sequential", "concurrent")) {
    chat <- new_async_fixture_chat()
    seen <- list(request = 0L, result = 0L)
    chat$on_tool_request(function(request) {
      seen$request <<- seen$request + 1L
    })
    chat$on_tool_result(function(result) {
      seen$result <<- seen$result + 1L
    })
    weather <- ellmer::tool(
      function(city) paste0("Sunny in ", city),
      name = "get_weather",
      description = "Get weather.",
      arguments = list(city = ellmer::type_string())
    )
    chat$register_tool(weather)

    calls <- 0L
    outcome <- httr2::with_mocked_responses(
      function(req) {
        calls <<- calls + 1L
        fixture_stream_response(
          if (calls == 1L) "tool-fragmented.sse" else "tool-final.sse"
        )
      },
      await_promise(coro::async_collect(chat$stream_async(
        "What is the weather?",
        tool_mode = mode,
        stream = "content"
      )))
    )

    expect_null(outcome$error)
    expect_length(outcome$value, 4L)
    expect_true(any(vapply(
      outcome$value,
      inherits,
      logical(1),
      what = "ellmer::ContentToolRequest"
    )))
    expect_true(any(vapply(
      outcome$value,
      inherits,
      logical(1),
      what = "ellmer::ContentToolResult"
    )))
    text <- paste0(vapply(
      outcome$value,
      getFromNamespace("codex_stream_chunk_text", "ellmercodex"),
      character(1)
    ), collapse = "")
    expect_match(text, "The weather result is sunny\\.")
    expect_identical(seen$request, 1L)
    expect_identical(seen$result, 1L)
    expect_identical(chat$last_turn()@text, "The weather result is sunny.")
  }
})

test_that("async structured output uses the stream-only Codex transport", {
  skip_if_not_installed("ellmer")

  chat <- new_async_fixture_chat()
  schema <- ellmer::type_object(
    name = ellmer::type_string(),
    age = ellmer::type_integer()
  )
  outcome <- httr2::with_mocked_responses(
    function(req) fixture_stream_response("structured-async-empty-terminal.sse"),
    await_promise(chat$chat_structured_async("Extract the person.", type = schema))
  )

  expect_null(outcome$error)
  expect_identical(outcome$value$name, "Susan")
  expect_identical(outcome$value$age, 13L)
  expect_true(inherits(chat$last_turn()@contents[[1L]], "ellmer::ContentJson"))
})

test_that("async stream cancellation does not force a partial turn repair", {
  skip_if_not_installed("ellmer")

  chat <- new_async_fixture_chat()
  original <- chat$stream_async
  rlang::env_binding_unlock(chat, "stream_async")
  chat$stream_async <- function(
    ...,
    tool_mode = c("concurrent", "sequential"),
    stream = c("text", "content"),
    controller = NULL
  ) {
    coro::async_generator(function() {
      coro::yield(if (identical(stream, "content")) {
        ellmer::ContentText("partial")
      } else {
        "partial"
      })
      controller$cancel()
    })()
  }
  rlang::env_binding_lock(chat, "stream_async")

  controller <- ellmer::stream_controller()
  outcome <- await_promise(coro::async_collect(
    chat$stream_async("cancel me", controller = controller)
  ))

  rlang::env_binding_unlock(chat, "stream_async")
  chat$stream_async <- original
  rlang::env_binding_lock(chat, "stream_async")
  expect_null(outcome$error)
  expect_identical(outcome$value[[1L]], "partial")
  expect_true(controller$cancelled)
})

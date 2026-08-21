testthat::test_that("SSE framing handles CRLF, event fields, and [DONE]", {
  events <- codex_parse_sse(fixture_text("stream-crlf.sse"))

  testthat::expect_s3_class(events, "codex_sse_events")
  testthat::expect_length(events, 4L)
  testthat::expect_identical(attr(events, "done_seen"), TRUE)
  testthat::expect_identical(events[[1L]]$type, "response.created")
  testthat::expect_identical(events[[2L]]$delta, "Hello ")
  testthat::expect_identical(events[[3L]]$delta, "from fixture")
  testthat::expect_identical(
    codex_parse_sse_response(events),
    "Hello from fixture"
  )
})

testthat::test_that("SSE data fields support JSON split across lines", {
  events <- codex_parse_sse(fixture_text("stream-multiline.sse"))
  testthat::expect_length(events, 3L)
  testthat::expect_identical(
    codex_parse_sse_response(events),
    "line one and line two"
  )
})

testthat::test_that("unknown event types are retained by framing and ignored by assembly", {
  value <- paste0(
    "event: response.metadata\n",
    "data: {\"type\":\"response.metadata\",\"metadata\":{\"fixture\":true}}\n\n",
    "data: {\"type\":\"response.output_text.delta\",\"delta\":\"ok\"}\n\n",
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  )
  events <- codex_parse_sse(value)
  testthat::expect_identical(events[[1L]]$type, "response.metadata")
  testthat::expect_identical(codex_parse_sse_response(events), "ok")
})

testthat::test_that("terminal response output is a fallback when no deltas exist", {
  events <- list(list(
    type = "response.completed",
    response = list(
      status = "completed",
      output = list(list(
        type = "message",
        content = list(list(type = "output_text", text = "terminal text"))
      ))
    )
  ))
  testthat::expect_identical(codex_parse_sse_response(events), "terminal text")
})

testthat::test_that("incomplete and failed events have dedicated conditions", {
  incomplete <- testthat::expect_error(
    codex_parse_sse_response(codex_parse_sse(fixture_text("stream-incomplete.sse"))),
    class = "codex_incomplete_error"
  )
  testthat::expect_s3_class(incomplete, "codex_incomplete_error")

  failed <- testthat::expect_error(
    codex_parse_sse_response(codex_parse_sse(fixture_text("stream-error.sse"))),
    class = "codex_generation_error"
  )
  testthat::expect_s3_class(failed, "codex_generation_error")
})

testthat::test_that("missing terminal, malformed JSON, and empty streams fail safely", {
  missing_terminal <- testthat::expect_error(
    codex_parse_sse_response(list(list(
      type = "response.output_text.delta",
      delta = "partial"
    ))),
    class = "codex_protocol_changed_error"
  )
  testthat::expect_s3_class(missing_terminal, "codex_protocol_changed_error")

  malformed <- testthat::expect_error(
    codex_parse_sse("data: definitely-not-json\n\n"),
    class = "codex_protocol_changed_error"
  )
  testthat::expect_s3_class(malformed, "codex_protocol_changed_error")

  empty <- testthat::expect_error(
    codex_parse_sse_response(list()),
    class = "codex_protocol_changed_error"
  )
  testthat::expect_s3_class(empty, "codex_protocol_changed_error")
})

testthat::test_that("SSE detection accepts media type parameters and safe sniffing", {
  testthat::expect_true(codex_is_sse_body("text/event-stream; charset=utf-8", ""))
  testthat::expect_true(codex_is_sse_body(NA_character_, "\ufeff data: {}"))
  testthat::expect_true(codex_is_sse_body(NA_character_, ": heartbeat\n\n"))
  testthat::expect_false(codex_is_sse_body("application/json", '{"output":[]}'))
})

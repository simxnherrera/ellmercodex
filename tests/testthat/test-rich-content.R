test_that("image and PDF inputs keep their OpenAI Responses representation", {
  skip_if_not_installed("ellmer")

  chat <- new_async_fixture_chat()
  image <- ellmer::ContentImageInline("image/png", "aGVsbG8=")
  pdf <- ellmer::ContentPDF("application/pdf", "cGRm", "fixture.pdf")
  seen <- NULL

  outcome <- httr2::with_mocked_responses(
    function(req) {
      seen <<- req
      fixture_stream_response("stream-async-empty-terminal.sse")
    },
    coro::collect(chat$stream(image, pdf))
  )

  expect_identical(
    sub("\\n$", "", paste0(outcome, collapse = "")),
    "Hello async"
  )
  input <- seen$body$data$input
  expect_identical(input[[1L]]$content[[1L]]$type, "input_image")
  expect_identical(input[[1L]]$content[[1L]]$image_url, "data:image/png;base64,aGVsbG8=")
  expect_identical(input[[2L]]$content[[1L]]$type, "input_file")
  expect_identical(input[[2L]]$content[[1L]]$filename, "fixture.pdf")
  expect_identical(
    input[[2L]]$content[[1L]]$file_data,
    "data:application/pdf;base64,cGRm"
  )
})

test_that("streamed text repair preserves terminal image content", {
  skip_if_not_installed("ellmer")

  chat <- new_async_fixture_chat()
  outcome <- httr2::with_mocked_responses(
    function(req) fixture_stream_response("image-output.sse"),
    coro::collect(chat$stream("Generate an image."))
  )

  expect_identical(
    sub("\\n$", "", paste0(outcome, collapse = "")),
    "Here is the image."
  )
  contents <- chat$last_turn()@contents
  expect_true(any(vapply(
    contents,
    inherits,
    logical(1),
    what = "ellmer::ContentImageInline"
  )))
  expect_identical(
    contents[[1L]]@text,
    "Here is the image."
  )
})

test_that("content streaming yields terminal images without text rendering", {
  skip_if_not_installed("ellmer")

  chat <- new_async_fixture_chat()
  outcome <- httr2::with_mocked_responses(
    function(req) fixture_stream_response("image-output.sse"),
    coro::collect(chat$stream("Generate an image.", stream = "content"))
  )

  expect_true(any(vapply(
    outcome,
    inherits,
    logical(1),
    what = "ellmer::ContentImageInline"
  )))
})

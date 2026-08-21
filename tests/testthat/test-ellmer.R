codex_ellmer_compatibility <- getFromNamespace("codex_ellmer_compatibility", "ellmercodex")
codex_ellmer_chat_openai <- getFromNamespace("codex_ellmer_chat_openai", "ellmercodex")
codex_patch_chat <- getFromNamespace("codex_patch_chat", "ellmercodex")
codex_echo <- getFromNamespace("codex_echo", "ellmercodex")
codex_repair_last_turn <- getFromNamespace("codex_repair_last_turn", "ellmercodex")
codex_stream_chunk_text <- getFromNamespace("codex_stream_chunk_text", "ellmercodex")

test_that("the installed ellmer release exposes the supported seam", {
  version <- codex_ellmer_compatibility()

  expect_gte(version, numeric_version("0.4.2"))
  expect_lt(version, numeric_version("0.5.0"))
  exports <- getNamespaceExports("ellmer")
  expect_true(all(c("chat_openai", "AssistantTurn", "ContentText") %in% exports))
})

test_that("the public OpenAI factory creates an offline-compatible Chat", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  local_mocked_bindings(codex_auth = function() auth, .package = "ellmercodex")
  chat <- codex_ellmer_chat_openai(model = "fixture-model", auth = auth)

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_identical(provider@service_tier, "default")
  expect_true(grepl("/backend-api/codex$", provider@base_url))
  expect_identical(provider@extra_headers[["ChatGPT-Account-Id"]], "fixture-account")
  expect_identical(provider@extra_headers[["originator"]], "ellmercodex")
})

test_that("Codex compatibility repairs streamed text for chat and history", {
  skip_if_not_installed("ellmer")

  chat <- ellmer::chat_openai(
    credentials = function() "fixture-access-token",
    model = "fixture-model",
    base_url = "http://127.0.0.1:1",
    service_tier = "default",
    echo = "none"
  )

  # Keep this fixture entirely offline; the real credentials callback is
  # exercised by chat_codex() only after an explicit login.
  fake_auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )

  fixture_stream <- function(
    ...,
    stream = c("text", "content"),
    controller = NULL
  ) {
    stream <- match.arg(stream)
    chat$set_turns(c(
      chat$get_turns(),
      list(
        ellmer::UserTurn(list(ellmer::ContentText("fixture prompt"))),
        ellmer::AssistantTurn()
      )
    ))

    chunks <- if (identical(stream, "content")) {
      list(ellmer::ContentText("Hello "), ellmer::ContentText("from R"))
    } else {
      list("Hello ", "from R")
    }
    coro::generator(function() {
      for (chunk in chunks) coro::yield(chunk)
    })()
  }

  rlang::env_binding_unlock(chat, "stream")
  chat$stream <- fixture_stream
  rlang::env_binding_lock(chat, "stream")
  chat <- codex_patch_chat(chat)

  first <- chat$chat("ignored")
  expect_s3_class(first, "ellmer_output")
  expect_identical(as.character(first), "Hello from R")
  expect_identical(chat$last_turn()@text, "Hello from R")

  streamed <- coro::collect(chat$stream("ignored", stream = "content"))
  streamed_text <- paste0(vapply(streamed, codex_stream_chunk_text, character(1)), collapse = "")
  expect_identical(streamed_text, "Hello from R")
  expect_identical(chat$last_turn()@text, "Hello from R")
  expect_length(chat$get_turns(), 4L)
  expect_identical(attr(chat, "ellmercodex_compatibility"), "buffered-terminal-output")
})

test_that("chat argument and compatibility failures use user-facing conditions", {
  fake_auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  expect_error(codex_echo("all"), class = "codex_chat_argument_error")
  expect_error(
    codex_repair_last_turn(
      ellmer::chat_openai(credentials = function() fake_auth$access_token),
      ""
    ),
    class = "codex_protocol_changed_error"
  )
})

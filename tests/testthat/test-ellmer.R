codex_ellmer_compatibility <- getFromNamespace("codex_ellmer_compatibility", "ellmercodex")
codex_ellmer_chat_openai <- getFromNamespace("codex_ellmer_chat_openai", "ellmercodex")
codex_patch_chat <- getFromNamespace("codex_patch_chat", "ellmercodex")
codex_echo <- getFromNamespace("codex_echo", "ellmercodex")

test_that("the installed ellmer release exposes the supported seam", {
  version <- codex_ellmer_compatibility()

  expect_identical(as.character(version), "0.4.2")
  exports <- getNamespaceExports("ellmer")
  expect_true(all(c("chat_openai", "AssistantTurn", "ContentText") %in% exports))
})

test_that("the public OpenAI factory creates an offline-compatible Chat", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  local_mocked_bindings(
    codex_auth = function(...) stop("fixture test must not read credentials"),
    .package = "ellmercodex"
  )
  chat <- codex_ellmer_chat_openai(model = "fixture-model", auth = auth)

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_identical(provider@service_tier, "default")
  expect_true(grepl("/backend-api/codex$", provider@base_url))
  expect_identical(provider@extra_headers[["ChatGPT-Account-Id"]], "fixture-account")
  expect_identical(provider@extra_headers[["originator"]], "ellmercodex")
  expect_identical(provider@credentials(), "fixture-access-token")
})

test_that("ellmer reasoning effort is forwarded without translation", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  chat <- codex_ellmer_chat_openai(
    model = "fixture-model",
    auth = auth,
    params = ellmer::params(reasoning_effort = "high")
  )
  provider <- chat$get_provider()
  expect_identical(provider@params$reasoning_effort, "high")
})

test_that("Codex compatibility keeps the public Chat lifecycle and merges streamed text", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      account_id = "fixture-account",
      expires_at = as.numeric(Sys.time()) + 3600
    ),
    class = c("codex_auth", "list")
  )
  chat <- codex_patch_chat(codex_ellmer_chat_openai(model = "fixture-model", auth = auth))

  answer <- httr2::with_mocked_responses(
    function(req) fixture_stream_response("stream-async-empty-terminal.sse"),
    chat$chat("Say hello.")
  )

  expect_s3_class(answer, "ellmer_output")
  expect_identical(as.character(answer), "Hello async")
  expect_identical(chat$last_turn()@text, "Hello async")
  expect_true(is.finite(chat$last_turn()@duration))
  expect_identical(chat$last_turn()@finish_reason, "success")
  expect_identical(attr(chat, "ellmercodex_compatibility"), "ellmer-0.4.2-provider-stream")
})

test_that("Codex structured output uses ellmer conversion after SSE merge", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      account_id = "fixture-account",
      expires_at = as.numeric(Sys.time()) + 3600
    ),
    class = c("codex_auth", "list")
  )
  chat <- codex_patch_chat(codex_ellmer_chat_openai(model = "fixture-model", auth = auth))
  value <- httr2::with_mocked_responses(
    function(req) fixture_stream_response("structured-async-empty-terminal.sse"),
    chat$chat_structured(
      "Extract the person.",
      type = ellmer::type_object(
        name = ellmer::type_string(),
        age = ellmer::type_number()
      )
    )
  )

  expect_identical(value$name, "Susan")
  expect_identical(value$age, 13L)
  expect_true(inherits(chat$last_turn()@contents[[1L]], "ellmer::ContentJson"))
})

test_that("chat argument and compatibility failures use user-facing conditions", {
  fake_auth <- structure(
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  expect_identical(codex_echo("all"), "all")
  expect_error(
    ellmercodex::chat_codex(effort = ""),
    class = "codex_chat_argument_error"
  )
  expect_error(
    ellmercodex::chat_codex(
      effort = "high",
      params = list(reasoning_effort = "low")
    ),
    class = "codex_chat_argument_error"
  )
})

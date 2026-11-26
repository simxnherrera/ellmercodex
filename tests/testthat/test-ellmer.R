skip_if_ellmer_contract_changed()

codex_ellmer_compatibility <- getFromNamespace("codex_ellmer_compatibility", "ellmercodex")
codex_ellmer_chat_openai <- getFromNamespace("codex_ellmer_chat_openai", "ellmercodex")
codex_patch_chat <- getFromNamespace("codex_patch_chat", "ellmercodex")
codex_echo <- getFromNamespace("codex_echo", "ellmercodex")

test_that("the installed ellmer release exposes the supported seam", {
  version <- codex_ellmer_compatibility()

  expect_gte(version, package_version("0.5.1"))
  exports <- getNamespaceExports("ellmer")
  expect_true(all(c("chat_openai", "AssistantTurn", "ContentText") %in% exports))
})

test_that("the public OpenAI factory creates an offline-compatible Chat", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(access_token = "fixture-access-token", client_id = "oaiapp_fixtureclient"),
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
  expect_identical(provider@base_url, "https://api.openai.com/v1")
  expect_setequal(names(provider@extra_headers), c("Accept", "User-Agent"))
  expect_identical(provider@credentials(), "fixture-access-token")
})

test_that("ellmer reasoning effort is forwarded without translation", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(access_token = "fixture-access-token", client_id = "oaiapp_fixtureclient"),
    class = c("codex_auth", "list")
  )
  chat <- codex_ellmer_chat_openai(
    model = "fixture-model",
    auth = auth,
    params = ellmer::params(reasoning_effort = "high")
  )
  provider <- chat$get_provider()
  expect_identical(chat$get_model_object()@params$reasoning_effort, "high")
})

test_that("Codex compatibility keeps the public Chat lifecycle and merges streamed text", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      client_id = "oaiapp_fixtureclient",
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
  expect_identical(attr(chat, "ellmercodex_compatibility"), "ellmer-0.5.0-provider-stream")
})

test_that("Codex structured output uses ellmer conversion after SSE merge", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      client_id = "oaiapp_fixtureclient",
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
    list(access_token = "fixture-access-token", client_id = "oaiapp_fixtureclient"),
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

test_that("streamed text deltas are merged into one partial content", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(access_token = "fixture-access-token", client_id = "oaiapp_fixtureclient"),
    class = c("codex_auth", "list")
  )
  chat <- codex_ellmer_chat_openai(model = "fixture-model", auth = auth)
  accumulator_class <- utils::getFromNamespace("TurnAccumulator", "ellmer")
  private <- chat$.__enclos_env__$private
  accumulator <- accumulator_class$new(
    chat, private, ellmer::stream_controller(),
    turns = list()
  )
  accumulator$begin_turn(ellmer::UserTurn(list(ellmer::ContentText("Hi"))))

  for (piece in c("Hel", "lo", " wor", "ld")) {
    codex_accumulator_update(accumulator, ellmer::ContentText(piece))
  }
  codex_accumulator_update(accumulator, ellmer::ContentThinking("hmm"))
  codex_accumulator_update(accumulator, ellmer::ContentText("!"))

  contents <- private$.turns[[accumulator$turn_idx]]@contents
  expect_length(contents, 3L)
  expect_identical(contents[[1L]]@text, "Hello world")
  expect_true(inherits(contents[[2L]], "ellmer::ContentThinking"))
  expect_identical(contents[[3L]]@text, "!")
})

test_that("a long streamed answer is assembled in full", {
  skip_if_not_installed("ellmer")

  auth <- structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      client_id = "oaiapp_fixtureclient",
      expires_at = as.numeric(Sys.time()) + 3600
    ),
    class = c("codex_auth", "list")
  )
  pieces <- sprintf("w%04d ", seq_len(2000))
  body <- paste0(
    paste0(
      'data: {"type":"response.output_text.delta","item_id":"msg_1","delta":"',
      pieces, '"}\n\n',
      collapse = ""
    ),
    'data: {"type":"response.completed","response":{"id":"resp_fixture",',
    '"model":"fixture-model","status":"completed","output":[],',
    '"usage":{"input_tokens":5,"output_tokens":2000}}}\n\ndata: [DONE]\n\n'
  )
  response <- function(req) {
    connection <- rawConnection(charToRaw(body), "rb")
    getFromNamespace("new_response", "httr2")(
      method = "POST",
      url = "http://127.0.0.1:1",
      status_code = 200L,
      headers = list(`Content-Type` = "text/event-stream"),
      body = getFromNamespace("StreamingBody", "httr2")$new(connection)
    )
  }
  chat <- codex_patch_chat(codex_ellmer_chat_openai(model = "fixture-model", auth = auth))
  answer <- httr2::with_mocked_responses(response, chat$chat("Count."))

  expect_identical(as.character(answer), paste0(pieces, collapse = ""))
})

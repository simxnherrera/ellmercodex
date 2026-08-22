codex_interface <- getFromNamespace("codex_ellmer_chat_interface", "ellmercodex")
codex_chat_openai <- getFromNamespace("codex_ellmer_chat_openai", "ellmercodex")
codex_patch_chat <- getFromNamespace("codex_patch_chat", "ellmercodex")

interface_fixture_auth <- function(expires_at = as.numeric(Sys.time()) + 3600) {
  structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      account_id = "fixture-account",
      expires_at = expires_at
    ),
    class = c("codex_auth", "list")
  )
}

interface_fixture_chat <- function(auth = interface_fixture_auth()) {
  codex_patch_chat(codex_chat_openai(model = "fixture-model", auth = auth))
}

test_that("the complete installed ellmer Chat public interface is present", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  inventory <- codex_interface()
  expected <- names(inventory$methods)
  installed_methods <- getFromNamespace("Chat", "ellmer")$public_methods

  expect_identical(as.character(utils::packageVersion("ellmer")), "0.4.2")
  expect_true(all(vapply(expected, function(name) is.function(chat[[name]]), logical(1))))
  expect_true(all(vapply(expected, function(name) {
    identical(
      names(formals(chat[[name]])) %||% character(),
      inventory$formal_names[[name]] %||% character()
    )
  }, logical(1))))
  expect_true(all(vapply(expected, function(name) {
    identical(formals(chat[[name]]), formals(installed_methods[[name]]))
  }, logical(1))))
  expect_identical(inventory$public_fields, character())
  expect_true(all(expected %in% names(chat)))
  expect_true(inherits(chat$get_provider(), "ellmercodex::CodexProvider"))
})

test_that("Chat state, metadata, model configuration, and history remain ellmer state", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  expect_identical(chat$get_system_prompt(), NULL)
  expect_identical(chat$get_model(), "fixture-model")
  chat$set_model("fixture-model-2")
  expect_identical(chat$get_model(), "fixture-model-2")
  chat$set_system_prompt("Be concise.")
  expect_identical(chat$get_system_prompt(), "Be concise.")

  assistant <- ellmer::AssistantTurn(
    contents = list(ellmer::ContentText("fixture")),
    tokens = c(10, 4, 2),
    cost = getFromNamespace("dollars", "ellmer")(NA_real_),
    duration = 1.25,
    finish_reason = "success"
  )
  chat$add_turn(
    ellmer::UserTurn(list(ellmer::ContentText("prompt"))),
    assistant
  )
  expect_identical(chat$last_turn()@text, "fixture")
  expect_identical(length(chat$get_turns()), 2L)
  expect_identical(chat$get_tokens()$input[[1L]], 10)
  expect_identical(chat$get_tokens()$output[[1L]], 4)
  expect_identical(chat$get_tokens()$cached_input[[1L]], 2)
  expect_length(chat$get_cost(include = "last"), 1L)
})

test_that("Chat cloning is independent and never retains the original Chat closure", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  chat$set_turns(list(ellmer::UserTurn(list(ellmer::ContentText("original")))))
  clone <- chat$clone()
  clone$set_turns(list(ellmer::UserTurn(list(ellmer::ContentText("clone")))))
  clone$set_model("clone-model")

  expect_identical(chat$get_turns()[[1L]]@text, "original")
  expect_identical(clone$get_turns()[[1L]]@text, "clone")
  expect_identical(chat$get_model(), "fixture-model")
  expect_identical(clone$get_model(), "clone-model")
  expect_false(identical(chat$.__enclos_env__$private, clone$.__enclos_env__$private))
  expect_true(identical(
    environment(chat$.__enclos_env__$private$submit_turns)$self,
    chat
  ))
  expect_true(identical(
    environment(clone$.__enclos_env__$private$submit_turns)$self,
    clone
  ))
  expect_true(identical(
    environment(chat$.__enclos_env__$private$chat_impl)$self,
    chat
  ))
  expect_true(identical(
    environment(clone$.__enclos_env__$private$chat_impl)$self,
    clone
  ))
  expect_false(identical(
    environment(clone$.__enclos_env__$private$submit_turns)$self,
    chat
  ))
  expect_false(identical(
    environment(clone$.__enclos_env__$private$chat_impl)$self,
    chat
  ))
})

test_that("ordered Codex content preserves text, tool, image, and later text", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  provider <- chat$get_provider()
  events <- list(
    list(type = "response.output_text.delta", delta = "Before. "),
    list(
      type = "response.output_item.added",
      item = list(
        type = "function_call", id = "fc_order", call_id = "call_order",
        name = "get_weather", arguments = "{}"
      )
    ),
    list(type = "response.output_text.delta", delta = "Between. "),
    list(
      type = "response.output_item.done",
      item = list(
        type = "image_generation_call", id = "img_order",
        output_format = "png", result = "aGVsbG8="
      )
    ),
    list(type = "response.output_text.delta", delta = "After."),
    list(
      type = "response.completed",
      response = list(status = "completed", output = list(
        list(type = "function_call", id = "fc_order", call_id = "call_order",
             name = "get_weather", arguments = "{}"),
        list(type = "image_generation_call", id = "img_order",
             output_format = "png", result = "aGVsbG8=")
      ))
    )
  )
  result <- NULL
  for (event in events) {
    result <- ellmer:::stream_merge_chunks(provider, result, event)
  }
  turn <- ellmer:::value_turn(provider, result)

  expect_length(turn@contents, 5L)
  expect_identical(turn@contents[[1L]]@text, "Before. ")
  expect_true(inherits(turn@contents[[2L]], "ellmer::ContentToolRequest"))
  expect_identical(turn@contents[[3L]]@text, "Between. ")
  expect_true(inherits(turn@contents[[4L]], "ellmer::ContentImageInline"))
  expect_identical(turn@contents[[5L]]@text, "After.")
})

test_that("content streaming exposes tools once and preserves unknown output", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  provider <- chat$get_provider()
  tool_content <- ellmer:::stream_content(
    provider,
    list(
      type = "response.output_item.done",
      item = list(
        type = "function_call", id = "fc_stream", call_id = "call_stream",
        name = "get_weather", arguments = "{}"
      )
    )
  )
  unknown_content <- ellmer:::stream_content(
    provider,
    list(
      type = "response.output_item.done",
      item = list(type = "computer_call", id = "terminal_1", output = "ls")
    )
  )

  expect_true(inherits(tool_content, "ellmer::ContentToolRequest"))
  expect_true(inherits(unknown_content, "ellmer::ContentJson"))
  expect_identical(unknown_content@data$type, "computer_call")
})

test_that("usage and finish metadata are retained by the Codex converter", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  provider <- chat$get_provider()
  result <- NULL
  result <- ellmer:::stream_merge_chunks(
    provider,
    result,
    list(type = "response.output_text.delta", delta = "ok")
  )
  result <- ellmer:::stream_merge_chunks(
    provider,
    result,
    list(
      type = "response.completed",
      response = list(
        status = "completed",
        service_tier = "default",
        usage = list(
          input_tokens = 10,
          output_tokens = 4,
          input_tokens_details = list(cached_tokens = 2)
        ),
        output = list()
      )
    )
  )
  turn <- ellmer:::value_turn(provider, result)

  expect_identical(as.numeric(turn@tokens), c(8, 4, 2))
  expect_identical(turn@finish_reason, "success")
  expect_identical(turn@json$usage$input_tokens, 10)
  expect_true(inherits(turn@cost, "ellmer_dollars"))
})

test_that("expired injected credentials refresh once without keyring re-entry", {
  skip_if_not_installed("ellmer")

  auth <- interface_fixture_auth(expires_at = as.numeric(Sys.time()) - 3600)
  refreshed <- interface_fixture_auth(expires_at = as.numeric(Sys.time()) + 3600)
  refresh_calls <- 0L
  local_mocked_bindings(
    codex_refresh = function(value, persist = TRUE) {
      refresh_calls <<- refresh_calls + 1L
      refreshed
    },
    codex_credentials_load = function(...) stop("keyring re-entry"),
    .package = "ellmercodex"
  )

  chat <- interface_fixture_chat(auth)
  provider <- chat$get_provider()
  expect_identical(provider@credentials(), "fixture-access-token")
  expect_identical(provider@credentials(), "fixture-access-token")
  expect_identical(refresh_calls, 1L)
})

test_that("a new user turn closes dangling tool requests through ellmer", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  dangling <- ellmer::ContentToolRequest(
    id = "dangling-call",
    name = "get_weather",
    arguments = list(city = "Montevideo")
  )
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("old prompt"))),
    ellmer::AssistantTurn(contents = list(dangling), finish_reason = "tool_use")
  ))
  seen <- NULL
  answer <- httr2::with_mocked_responses(
    function(req) {
      seen <<- req
      fixture_stream_response("tool-final.sse")
    },
    chat$chat("continue")
  )

  expect_identical(as.character(answer), "The weather result is sunny.")
  input <- seen$body$data$input
  expect_true(any(vapply(input, function(item) {
    is.list(item) && identical(item$type, "function_call_output") &&
      identical(item$call_id, "dangling-call")
  }, logical(1))))
})

test_that("cancellation stops a tool round before another Codex request", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  controller <- ellmer::stream_controller()
  tool <- ellmer::tool(
    function(city) paste("fixture result", city),
    name = "get_weather",
    description = "Fixture tool.",
    arguments = list(city = ellmer::type_string())
  )
  chat$register_tool(tool)
  chat$on_tool_request(function(request) controller$cancel())

  requests <- 0L
  chunks <- httr2::with_mocked_responses(
    function(req) {
      requests <<- requests + 1L
      if (requests == 1L) {
        fixture_stream_response("tool-no-text.sse")
      } else {
        stop("cancellation should prevent a second Codex request")
      }
    },
    coro::collect(chat$stream(
      "Try the tool.",
      stream = "content",
      controller = controller
    ))
  )

  expect_true(controller$cancelled)
  expect_identical(requests, 1L)
  expect_true(any(vapply(
    chunks,
    inherits,
    logical(1),
    what = "ellmer::ContentToolRequest"
  )))
  expect_true(inherits(
    chat$last_turn()@contents[[1L]],
    "ellmer::ContentToolRequest"
  ))
})

test_that("non-streaming ellmer helper paths fail explicitly before network I/O", {
  skip_if_not_installed("ellmer")

  chat <- interface_fixture_chat()
  provider <- chat$get_provider()
  expect_false(ellmer:::has_batch_support(provider))
  expect_error(
    ellmer:::chat_request(
      provider,
      stream = FALSE,
      turns = list(ellmer::UserTurn(list(ellmer::ContentText("fixture"))))
    ),
    class = "codex_ellmer_parallel_batch_blocker"
  )
  expect_error(
    ellmer::parallel_chat(chat, prompts = list("fixture")),
    class = "codex_ellmer_parallel_batch_blocker"
  )
})

codex_echo <- function(echo, default = "none") {
  if (is.null(echo)) echo <- default
  if (isTRUE(echo)) echo <- "output"
  if (isFALSE(echo)) echo <- "none"
  if (identical(echo, "text")) echo <- "output"
  if (!is.character(echo) || length(echo) != 1L ||
    !echo %in% c("none", "output")) {
    rlang::abort(
      "`echo` must be one of \"none\" or \"output\".",
      class = "codex_chat_argument_error"
    )
  }
  echo
}

codex_stream_chunk_text <- function(chunk) {
  if (is.character(chunk)) return(paste0(chunk, collapse = ""))
  if (inherits(chunk, "ellmer::ContentText")) return(chunk@text)
  ""
}

codex_repair_last_turn <- function(chat, text) {
  if (!is.character(text) || length(text) != 1L || !nzchar(text)) {
    rlang::abort(
      "The Codex stream completed without output text.",
      class = "codex_protocol_changed_error"
    )
  }

  turns <- chat$get_turns()
  if (length(turns) == 0L || !inherits(turns[[length(turns)]], "ellmer::AssistantTurn")) {
    rlang::abort(
      "ellmer did not record the expected assistant turn.",
      class = "codex_ellmer_compatibility_error"
    )
  }

  previous <- turns[[length(turns)]]
  turns[[length(turns)]] <- ellmer::AssistantTurn(
    contents = list(ellmer::ContentText(text)),
    json = previous@json,
    tokens = previous@tokens,
    cost = previous@cost,
    duration = previous@duration,
    finish_reason = previous@finish_reason
  )
  chat$set_turns(turns)
  invisible(text)
}

codex_chat_error <- function(error) {
  detail <- codex_sanitize_error_detail(conditionMessage(error))
  message <- "The Codex ellmer request failed."
  if (!is.null(detail) && nzchar(detail)) message <- paste(message, detail)
  rlang::abort(message, class = "codex_chat_error", parent = NULL)
}

codex_patch_chat <- function(chat, default_echo = "none") {
  stopifnot(inherits(chat, "Chat"))
  original_stream <- chat$stream

  patched_chat <- function(..., echo = NULL) {
    echo <- codex_echo(echo, default = default_echo)
    chunks <- tryCatch(
      coro::collect(original_stream(..., stream = "text")),
      error = codex_chat_error
    )
    text <- paste0(vapply(chunks, codex_stream_chunk_text, character(1)), collapse = "")
    codex_repair_last_turn(chat, text)

    value <- structure(text, class = "ellmer_output")
    if (identical(echo, "output")) {
      cat(text, "\n", sep = "")
      invisible(value)
    } else {
      value
    }
  }

  patched_stream <- function(
    ...,
    stream = c("text", "content"),
    controller = NULL
  ) {
    stream <- match.arg(stream)
    delegate <- original_stream(..., stream = stream, controller = controller)

    coro::generator(function() {
      pieces <- character()
      repeat {
        chunk <- tryCatch(delegate(), error = codex_chat_error)
        if (coro::is_exhausted(chunk)) break
        pieces <- c(pieces, codex_stream_chunk_text(chunk))
        coro::yield(chunk)
      }
      codex_repair_last_turn(chat, paste0(pieces, collapse = ""))
    })()
  }

  for (name in c("chat", "stream")) unlockBinding(name, chat)
  chat$chat <- patched_chat
  chat$stream <- patched_stream
  for (name in c("chat", "stream")) lockBinding(name, chat)

  attr(chat, "ellmercodex_compatibility") <- "buffered-terminal-output"
  chat
}

chat_codex <- function(
  system_prompt = NULL,
  model = NULL,
  echo = c("none", "output")
) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    rlang::abort(
      "`chat_codex()` requires the ellmer package.",
      class = "codex_ellmer_missing"
    )
  }

  echo <- match.arg(echo)
  auth <- codex_auth()
  model <- model %||% codex_default_model()

  chat <- ellmer::chat_openai(
    system_prompt = system_prompt,
    base_url = sub("/responses$", "", codex_responses_url()),
    credentials = function() codex_auth()$access_token,
    model = model,
    api_headers = c(
      `ChatGPT-Account-Id` = auth$account_id,
      originator = codex_originator(),
      `OpenAI-Beta` = codex_protocol_version(),
      Accept = "text/event-stream"
    ),
    service_tier = "default",
    echo = "none"
  )

  codex_patch_chat(chat, default_echo = echo)
}

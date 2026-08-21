codex_echo <- function(echo, default = "none") {
  if (is.null(echo)) echo <- default
  # A missing argument arrives as the usual choices vector. Match the first
  # choice explicitly so errors remain package conditions rather than base
  # `match.arg()` errors.
  if (is.character(echo) && length(echo) > 1L &&
        all(echo %in% c("none", "output"))) {
    echo <- echo[[1L]]
  }
  if (isTRUE(echo)) echo <- "output"
  if (isFALSE(echo)) echo <- "none"
  if (identical(echo, "text")) echo <- "output"
  if (!is.character(echo) || length(echo) != 1L || is.na(echo) ||
        !echo %in% c("none", "output")) {
    rlang::abort(
      "`echo` must be one of \"none\" or \"output\".",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  echo
}

codex_stream_chunk_text <- function(chunk) {
  if (is.character(chunk)) {
    return(paste0(chunk, collapse = ""))
  }
  if (inherits(chunk, "ellmer::ContentText")) {
    return(chunk@text)
  }
  ""
}

codex_repair_last_turn <- function(chat, text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) {
    rlang::abort(
      "The Codex stream completed without output text.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }

  turns <- tryCatch(chat$get_turns(), error = function(error) NULL)
  if (!is.list(turns) || length(turns) == 0L ||
        !inherits(turns[[length(turns)]], "ellmer::AssistantTurn")) {
    rlang::abort(
      "ellmer did not record the expected assistant turn.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  previous <- turns[[length(turns)]]
  repaired <- tryCatch(
    ellmer::AssistantTurn(
      contents = list(ellmer::ContentText(text)),
      json = previous@json,
      tokens = previous@tokens,
      cost = previous@cost,
      duration = previous@duration,
      finish_reason = previous@finish_reason
    ),
    error = function(error) NULL
  )
  if (is.null(repaired)) {
    rlang::abort(
      "The ellmer assistant turn could not be repaired from streamed text.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  updated <- turns
  updated[[length(updated)]] <- repaired
  ok <- tryCatch(
    {
      chat$set_turns(updated)
      TRUE
    },
    error = function(error) FALSE
  )
  if (!isTRUE(ok)) {
    rlang::abort(
      "ellmer could not save the repaired assistant turn.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  invisible(text)
}

codex_chat_error <- function(error) {
  detail <- tryCatch(
    codex_sanitize_error_detail(conditionMessage(error)),
    error = function(inner_error) NULL
  )
  message <- "The Codex ellmer request failed."
  if (!is.null(detail) && length(detail) == 1L && nzchar(detail)) {
    message <- paste(message, detail)
  }
  rlang::abort(message, class = "codex_chat_error", parent = NULL)
}

codex_patch_chat <- function(chat, default_echo = "none") {
  if (!inherits(chat, "Chat")) {
    rlang::abort(
      "The installed ellmer factory did not return a Chat object.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  codex_ellmer_chat_methods(chat)
  default_echo <- codex_echo(default_echo)

  if (identical(attr(chat, "ellmercodex_compatibility"), "buffered-terminal-output")) {
    return(chat)
  }

  original_stream <- chat$stream
  original_chat <- chat$chat
  if (!is.function(original_stream) || !is.function(original_chat)) {
    rlang::abort(
      "The ellmer Chat object does not expose callable chat and stream methods.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

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
    delegate <- tryCatch(
      original_stream(..., stream = stream, controller = controller),
      error = codex_chat_error
    )

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

  method_names <- c("chat", "stream")
  locked <- rlang::env_binding_are_locked(chat, method_names)
  if (any(locked)) {
    rlang::env_binding_unlock(chat, method_names[locked])
    on.exit(
      {
        for (name in method_names) {
          if (!rlang::env_binding_are_locked(chat, name)) {
            rlang::env_binding_lock(chat, name)
          }
        }
      },
      add = TRUE
    )
  }
  chat$chat <- patched_chat
  chat$stream <- patched_stream
  if (any(locked)) {
    rlang::env_binding_lock(chat, method_names[locked])
    on.exit(NULL, add = FALSE)
  }

  attr(chat, "ellmercodex_compatibility") <- "buffered-terminal-output"
  chat
}

#' Create an experimental Codex chat backed by ellmer
#'
#' `chat_codex()` returns a normal ellmer `Chat` object configured for the
#' observed Codex subscription transport. It does not start browser
#' authentication. Call [codex_login()] explicitly first when no stored
#' credential is available; an existing credential is loaded and refreshed as
#' needed.
#'
#' The returned chat supports ordinary text `$chat()`, text or content
#' `$stream()`, and multi-turn history. The compatibility layer buffers the
#' public ellmer stream and repairs the final assistant turn because the
#' observed Codex terminal event can omit the output that was present in its
#' preceding deltas. Structured output, asynchronous methods, and tool calling
#' are outside this experimental interface.
#'
#' @param system_prompt Optional system prompt passed to ellmer.
#' @param model Optional Codex model name. If omitted, the package default is
#'   used.
#' @param echo One of `"none"` or `"output"`; controls whether `$chat()`
#'   prints the completed text. The compatibility wrapper accepts `TRUE`,
#'   `FALSE`, and `"text"` as aliases for `"output"`, `"none"`, and
#'   `"output"`, respectively.
#' @return An object inheriting from ellmer's `Chat` class.
#' @section Conditions:
#' Invalid arguments signal `codex_chat_argument_error`. Missing or
#' incompatible ellmer installations signal `codex_ellmer_missing` or
#' `codex_ellmer_compatibility_error`. Authentication failures found before
#' the Chat is constructed retain their package condition classes; errors while
#' delegating through the ellmer seam are sanitized as `codex_chat_error`.
#' @examplesIf interactive()
#' chat <- chat_codex(
#'   system_prompt = "Be concise.",
#'   model = Sys.getenv("ELLMERCODEX_MODEL", "gpt-5.6-luna")
#' )
#' chat$chat("Hello")
#' @export
chat_codex <- function(
  system_prompt = NULL,
  model = NULL,
  echo = c("none", "output")
) {
  echo <- codex_echo(echo)
  invalid_system_prompt <- !is.null(system_prompt) &&
    (!is.character(system_prompt) || length(system_prompt) != 1L || is.na(system_prompt))
  if (invalid_system_prompt) {
    rlang::abort(
      "`system_prompt` must be NULL or one string.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  invalid_model <- !is.null(model) &&
    (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model))
  if (invalid_model) {
    rlang::abort(
      "`model` must be NULL or one non-empty string.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }

  codex_ellmer_compatibility()
  auth <- codex_auth()
  if (is.null(model)) model <- codex_default_model()

  chat <- codex_ellmer_chat_openai(
    system_prompt = system_prompt,
    model = model,
    auth = auth
  )
  codex_patch_chat(chat, default_echo = echo)
}

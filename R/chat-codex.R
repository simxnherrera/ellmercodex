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

codex_structured_echo <- function(echo) {
  if (is.null(echo)) echo <- "none"
  if (is.character(echo) && length(echo) > 1L &&
        all(echo %in% c("none", "output", "all"))) {
    echo <- echo[[1L]]
  }
  if (identical(echo, "text")) echo <- "output"
  if (isTRUE(echo)) echo <- "output"
  if (isFALSE(echo)) echo <- "none"
  if (!is.character(echo) || length(echo) != 1L || is.na(echo) ||
      !echo %in% c("none", "output", "all")) {
    rlang::abort(
      "Structured `echo` must be one of \"none\", \"output\", or \"all\".",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  echo
}

codex_assistant_turn_replace <- function(chat, content) {
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
      contents = list(content),
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
      "The ellmer assistant turn could not be repaired from streamed content.",
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
  invisible(repaired)
}

codex_repair_last_turn <- function(chat, text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) {
    rlang::abort(
      "The Codex stream completed without output text.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }

  content <- tryCatch(
    ellmer::ContentText(text),
    error = function(error) NULL
  )
  if (is.null(content)) {
    rlang::abort(
      "The streamed Codex text could not be represented by ellmer.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  codex_assistant_turn_replace(chat, content)
  invisible(text)
}

codex_structured_json_text <- function(output) {
  if (!is.character(output) || length(output) == 0L) {
    return(NULL)
  }
  candidate <- trimws(paste0(output, collapse = "\n"))
  if (!nzchar(candidate)) return(NULL)

  candidates <- candidate
  fenced <- sub("^```(?:json)?[[:space:]]*", "", candidate, perl = TRUE)
  fenced <- sub("[[:space:]]*```$", "", fenced, perl = TRUE)
  candidates <- unique(c(candidates, trimws(fenced)))

  # Captured output can contain a harmless prefix/suffix from an ellmer
  # compatibility seam. Try the complete value first, then the outer JSON
  # object/array span.
  starts <- gregexpr("[\\[{]", candidate, perl = TRUE)[[1L]]
  ends <- gregexpr("[\\]}]", candidate, perl = TRUE)[[1L]]
  if (starts[[1L]] > 0L && ends[[1L]] > 0L) {
    candidates <- c(
      candidates,
      substring(candidate, starts[[1L]], max(ends[[1L]]))
    )
  }

  for (value in unique(candidates)) {
    parsed <- tryCatch(
      jsonlite::fromJSON(value, simplifyVector = FALSE),
      error = function(error) NULL
    )
    if (!is.null(parsed)) {
      return(list(text = value, data = parsed))
    }
  }
  NULL
}

codex_structured_content_json <- function(parsed, text) {
  codex_ellmer_structured_compatibility()
  constructor <- utils::getFromNamespace("ContentJson", "ellmer")
  tryCatch(
    constructor(data = parsed, string = text),
    error = function(error) {
      rlang::abort(
        "The structured Codex response could not be represented by ellmer.",
        class = "codex_ellmer_compatibility_error",
        parent = NULL
      )
    }
  )
}

codex_extract_structured <- function(chat, text, type, convert = TRUE) {
  parsed <- codex_structured_json_text(text)
  if (is.null(parsed)) {
    rlang::abort(
      "The Codex structured response was not valid JSON.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }

  provider <- chat$get_provider()
  needs_wrapper <- utils::getFromNamespace("type_needs_wrapper", "ellmer")(
    type,
    provider
  )
  extraction_type <- utils::getFromNamespace("wrap_type_if_needed", "ellmer")(
    type,
    needs_wrapper = needs_wrapper
  )
  content <- codex_structured_content_json(parsed$data, parsed$text)
  codex_assistant_turn_replace(chat, content)

  extractor <- utils::getFromNamespace("extract_data", "ellmer")
  tryCatch(
    extractor(
      chat$last_turn(),
      extraction_type,
      convert = convert,
      needs_wrapper = needs_wrapper
    ),
    error = function(error) {
      rlang::abort(
        "ellmer could not convert the Codex structured response.",
        class = "codex_chat_error",
        parent = NULL
      )
    }
  )
}

codex_capture_output <- function(fn) {
  if (!is.function(fn)) {
    rlang::abort(
      "The structured-output capture callback was invalid.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  output <- character()
  connection <- textConnection("output", "w", local = TRUE)
  sink(connection, type = "output")
  active <- TRUE
  finish <- function() {
    if (isTRUE(active)) {
      sink(type = "output")
      close(connection)
      active <<- FALSE
    }
  }
  on.exit(finish(), add = TRUE)

  value <- NULL
  error <- NULL
  tryCatch(
    value <- fn(),
    error = function(condition) error <<- condition
  )
  finish()
  list(value = value, output = output, error = error)
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
  codex_ellmer_structured_compatibility()
  default_echo <- codex_echo(default_echo)

  if (identical(attr(chat, "ellmercodex_compatibility"), "buffered-terminal-output")) {
    return(chat)
  }

  original_stream <- chat$stream
  original_chat <- chat$chat
  original_structured <- chat$chat_structured
  if (!is.function(original_stream) || !is.function(original_chat) ||
      !is.function(original_structured)) {
    rlang::abort(
      paste(
        "The ellmer Chat object does not expose callable chat, stream, and",
        "structured-chat methods."
      ),
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

  patched_chat_structured <- function(..., type, echo = "none", convert = TRUE) {
    echo <- codex_structured_echo(echo)
    outcome <- codex_capture_output(function() {
      original_structured(
        ...,
        type = type,
        # Codex requires streaming. Capture ellmer's streamed JSON and repair
        # the empty terminal turn below.
        echo = "output",
        convert = convert
      )
    })

    parsed <- codex_structured_json_text(outcome$output)
    value <- if (is.null(outcome$error)) {
      outcome$value
    } else if (!is.null(parsed)) {
      codex_extract_structured(chat, parsed$text, type, convert = convert)
    } else {
      codex_chat_error(outcome$error)
    }

    if (identical(echo, "output") || identical(echo, "all")) {
      if (!is.null(parsed)) {
        cat(parsed$text, "\n", sep = "")
      } else if (length(outcome$output) > 0L) {
        cat(outcome$output, sep = "\n")
        cat("\n")
      }
      invisible(value)
    } else {
      value
    }
  }

  method_names <- c("chat", "stream", "chat_structured")
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
  chat$chat_structured <- patched_chat_structured
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
#' `$stream()`, ellmer structured output, and multi-turn history. The
#' compatibility layer buffers the public ellmer stream and repairs the final
#' assistant turn because the observed Codex terminal event can omit the output
#' that was present in its preceding deltas. Structured output uses ellmer's
#' JSON-schema method and the same streamed-text repair. Asynchronous methods
#' and tool calling remain outside this experimental interface.
#'
#' @param system_prompt Optional system prompt passed to ellmer.
#' @param model Optional Codex model name. If omitted, the package default is
#'   used.
#' @param effort Optional Codex reasoning effort. It is forwarded through
#'   ellmer as `params(reasoning_effort = effort)` and should be one of the
#'   values advertised by [codex_models()] for the selected model.
#' @param params Optional ellmer model parameters, usually created with
#'   `ellmer::params()`. A supplied `reasoning_effort` must agree with
#'   `effort`, when both are provided.
#' @param api_args Optional named list of additional Responses arguments passed
#'   through ellmer on every request.
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
  echo = c("none", "output"),
  effort = NULL,
  params = NULL,
  api_args = list()
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
  if (!is.null(effort) &&
      (!is.character(effort) || length(effort) != 1L || is.na(effort) ||
       !nzchar(effort))) {
    rlang::abort(
      "`effort` must be NULL or one non-empty string.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  if (!is.null(params) && !is.list(params)) {
    rlang::abort(
      "`params` must be NULL or a list created by `ellmer::params()`.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  if (!is.list(api_args) || (length(api_args) > 0L && is.null(names(api_args)))) {
    rlang::abort(
      "`api_args` must be a named list.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  if (!is.null(effort) && !is.null(params$reasoning_effort) &&
      !identical(effort, params$reasoning_effort)) {
    rlang::abort(
      "`effort` and `params$reasoning_effort` must match when both are supplied.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  if (!is.null(effort)) {
    params <- params %||% list()
    params$reasoning_effort <- effort
  }

  codex_ellmer_compatibility()
  auth <- codex_auth()
  if (is.null(model)) model <- codex_default_model()

  chat <- codex_ellmer_chat_openai(
    system_prompt = system_prompt,
    model = model,
    auth = auth,
    params = params,
    api_args = api_args
  )
  codex_patch_chat(chat, default_echo = echo)
}

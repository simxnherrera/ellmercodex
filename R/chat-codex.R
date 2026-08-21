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

codex_stream_piece_for_history <- function(chat, chunk) {
  piece <- codex_stream_chunk_text(chunk)
  if (!identical(piece, "\n")) return(piece)
  last <- tryCatch(chat$last_turn(role = "assistant"), error = function(error) NULL)
  if (codex_assistant_turn_complete(last)) "" else piece
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

codex_assistant_indices <- function(chat) {
  turns <- tryCatch(chat$get_turns(), error = function(error) NULL)
  if (!is.list(turns) || length(turns) == 0L) return(integer())
  which(vapply(
    turns,
    function(turn) {
      identical(tryCatch(turn@role, error = function(error) NULL), "assistant")
    },
    logical(1)
  ))
}

codex_assistant_turn_complete <- function(turn) {
  inherits(turn, "ellmer::AssistantTurn") &&
    !inherits(turn, "ellmer::AssistantPartialTurn")
}

codex_repair_assistant_text <- function(chat, index, text) {
  if (!is.numeric(index) || length(index) != 1L || !is.finite(index) ||
      index < 1L || !is.character(text) || length(text) != 1L ||
      is.na(text) || !nzchar(text)) {
    return(invisible(FALSE))
  }

  turns <- tryCatch(chat$get_turns(), error = function(error) NULL)
  if (!is.list(turns) || index > length(turns)) return(invisible(FALSE))
  previous <- turns[[index]]
  if (!codex_assistant_turn_complete(previous)) return(invisible(FALSE))

  content <- tryCatch(ellmer::ContentText(text), error = function(error) NULL)
  if (is.null(content)) {
    rlang::abort(
      "The streamed Codex text could not be represented by ellmer.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  contents <- previous@contents
  is_text <- vapply(
    contents,
    function(value) inherits(value, "ellmer::ContentText"),
    logical(1)
  )
  text_indices <- which(is_text)
  if (length(text_indices) > 0L) {
    first <- text_indices[[1L]]
    if (length(text_indices) > 1L) {
      contents <- contents[-text_indices[-1L]]
    }
    contents[[first]] <- content
  } else {
    is_tool_request <- vapply(
      contents,
      function(value) inherits(value, "ellmer::ContentToolRequest"),
      logical(1)
    )
    tool_index <- which(is_tool_request)
    if (length(tool_index) > 0L) {
      contents <- append(contents, list(content), after = tool_index[[1L]] - 1L)
    } else {
      contents[[length(contents) + 1L]] <- content
    }
  }

  json <- previous@json
  if (is.null(json)) json <- list()
  repaired <- tryCatch(
    ellmer::AssistantTurn(
      contents = contents,
      json = json,
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

  turns[[index]] <- repaired
  ok <- tryCatch(
    {
      chat$set_turns(turns)
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
  invisible(TRUE)
}

codex_async_stream_repair <- function(chat, delegate, controller) {
  coro::async_generator(function() {
    current_index <- NULL
    current_text <- character()
    repaired_indices <- integer()

    inspect_turn <- function() {
      indices <- codex_assistant_indices(chat)
      if (length(indices) == 0L) {
        return(list(index = NULL, complete = FALSE))
      }
      index <- indices[[length(indices)]]
      turns <- tryCatch(chat$get_turns(), error = function(error) NULL)
      turn <- if (is.list(turns) && index <= length(turns)) turns[[index]] else NULL
      list(
        index = index,
        complete = codex_assistant_turn_complete(turn)
      )
    }

    repair_ready_turn <- function(state) {
      index <- state$index
      if (is.null(index)) return(invisible())

      if (!is.null(current_index) && !identical(index, current_index)) {
        if (length(current_text) > 0L && !current_index %in% repaired_indices) {
          codex_repair_assistant_text(
            chat,
            current_index,
            paste0(current_text, collapse = "")
          )
          repaired_indices <<- c(repaired_indices, current_index)
        }
        current_text <<- character()
      }
      current_index <<- index

      if (isTRUE(state$complete) && length(current_text) > 0L &&
          !index %in% repaired_indices) {
        codex_repair_assistant_text(
          chat,
          index,
          paste0(current_text, collapse = "")
        )
        repaired_indices <<- c(repaired_indices, index)
      }
      invisible()
    }

    repeat {
      chunk <- tryCatch(
        coro::await(delegate()),
        error = function(error) codex_chat_error(error)
      )
      if (coro::is_exhausted(chunk)) break

      state <- inspect_turn()
      repair_ready_turn(state)
      piece <- codex_stream_chunk_text(chunk)
      # ellmer emits a bare newline between completed assistant turns. Keep it
      # in the public stream, but do not mistake it for model output when
      # rebuilding the assistant turn.
      if (nzchar(piece) && !(identical(piece, "\n") && isTRUE(state$complete))) {
        current_text <- c(current_text, piece)
      }
      repair_ready_turn(inspect_turn())
      coro::yield(chunk)
    }

    state <- inspect_turn()
    repair_ready_turn(state)
    if (!isTRUE(controller$cancelled) && length(current_text) == 0L) {
      last <- tryCatch(chat$last_turn(role = "assistant"), error = function(error) NULL)
      if (is.null(last) || length(last@contents) == 0L) {
        codex_repair_last_turn(chat, "")
      }
    }
  })()
}

codex_structured_async <- function(chat, dots, type, echo = "none", convert = TRUE) {
  echo <- codex_structured_echo(echo)
  if (!is.logical(convert) || length(convert) != 1L || is.na(convert)) {
    rlang::abort(
      "`convert` must be one TRUE or FALSE value.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }

  private <- codex_ellmer_chat_tool_compatibility(chat)
  as_user_turn <- codex_ellmer_internal("as_user_turn")
  finish_tools <- private$complete_dangling_tool_requests()
  user_turn <- as_user_turn(
    contents = c(finish_tools %||% list(), dots),
    check_empty = FALSE
  )

  provider <- chat$get_provider()
  type_needs_wrapper <- utils::getFromNamespace("type_needs_wrapper", "ellmer")
  wrap_type_if_needed <- utils::getFromNamespace("wrap_type_if_needed", "ellmer")
  needs_wrapper <- type_needs_wrapper(type, provider)
  extraction_type <- wrap_type_if_needed(type, needs_wrapper = needs_wrapper)

  delegate <- tryCatch(
    private$submit_turns_async(
      user_turn,
      type = extraction_type,
      stream = TRUE,
      echo = "none",
      controller = ellmer::stream_controller()
    ),
    error = codex_chat_error
  )
  done <- coro::async_collect(delegate)
  promises::then(
    done,
    function(chunks) {
      text <- paste0(
        vapply(chunks, codex_stream_chunk_text, character(1)),
        collapse = ""
      )
      parsed <- codex_structured_json_text(text)
      if (is.null(parsed)) {
        rlang::abort(
          "The Codex structured response was not valid JSON.",
          class = "codex_protocol_changed_error",
          parent = NULL
        )
      }
      value <- codex_extract_structured(chat, parsed$text, type, convert = convert)
      if (identical(echo, "output") || identical(echo, "all")) {
        cat(parsed$text, "\n", sep = "")
        invisible(value)
      } else {
        value
      }
    },
    function(error) codex_chat_error(error)
  )
}

codex_repair_last_turn <- function(chat, text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) {
    rlang::abort(
      "The Codex stream completed without output text.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }

  indices <- codex_assistant_indices(chat)
  if (length(indices) == 0L) {
    rlang::abort(
      "ellmer did not record the expected assistant turn.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  codex_repair_assistant_text(chat, indices[[length(indices)]], text)
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
  codex_ellmer_tool_compatibility()
  codex_ellmer_chat_tool_compatibility(chat)
  default_echo <- codex_echo(default_echo)

  if (identical(attr(chat, "ellmercodex_compatibility"), "buffered-terminal-output")) {
    return(chat)
  }

  original_stream <- chat$stream
  original_stream_async <- chat$stream_async
  original_chat <- chat$chat
  original_chat_async <- chat$chat_async
  original_structured <- chat$chat_structured
  original_structured_async <- chat$chat_structured_async
  if (!is.function(original_stream) || !is.function(original_stream_async) ||
      !is.function(original_chat) || !is.function(original_chat_async) ||
      !is.function(original_structured) || !is.function(original_structured_async)) {
    rlang::abort(
      paste(
        "The ellmer Chat object does not expose callable synchronous and",
        "asynchronous chat, stream, and structured-chat methods."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  patched_chat <- function(..., echo = NULL) {
    echo <- codex_echo(echo, default = default_echo)
    if (codex_tool_has_tools(chat)) {
      return(codex_tool_chat(chat, list(...), echo = echo))
    }
    chunks <- tryCatch(
      coro::collect(original_stream(..., stream = "text")),
      error = codex_chat_error
    )
    text <- paste0(
      vapply(
        chunks,
        function(chunk) codex_stream_piece_for_history(chat, chunk),
        character(1)
      ),
      collapse = ""
    )
    codex_repair_last_turn(chat, text)

    value <- structure(text, class = "ellmer_output")
    if (identical(echo, "output")) {
      cat(text, "\n", sep = "")
      invisible(value)
    } else {
      value
    }
  }

  patched_stream_async <- function(
    ...,
    tool_mode = c("concurrent", "sequential"),
    stream = c("text", "content"),
    controller = NULL
  ) {
    tool_mode <- match.arg(tool_mode)
    stream <- match.arg(stream)
    controller <- controller %||% ellmer::stream_controller()
    delegate <- tryCatch(
      original_stream_async(
        ...,
        tool_mode = tool_mode,
        stream = stream,
        controller = controller
      ),
      error = codex_chat_error
    )
    codex_async_stream_repair(chat, delegate, controller)
  }

  patched_chat_async <- function(
    ...,
    tool_mode = c("concurrent", "sequential")
  ) {
    tool_mode <- match.arg(tool_mode)
    stream <- patched_stream_async(
      ...,
      tool_mode = tool_mode,
      stream = "text",
      controller = NULL
    )
    done <- coro::async_collect(stream)
    promises::then(
      done,
      function(chunks) {
        assistant <- tryCatch(
          chat$last_turn(role = "assistant"),
          error = function(error) NULL
        )
        text <- if (!is.null(assistant)) assistant@text else paste0(
          vapply(chunks, codex_stream_chunk_text, character(1)),
          collapse = ""
        )
        if (!is.character(text) || length(text) != 1L || is.na(text)) text <- ""
        structure(text, class = "ellmer_output")
      },
      function(error) codex_chat_error(error)
    )
  }

  patched_stream <- function(
    ...,
    stream = c("text", "content"),
    controller = NULL
  ) {
    stream <- match.arg(stream)
    if (codex_tool_has_tools(chat)) {
      delegate <- codex_tool_stream(
        chat,
        list(...),
        stream = stream,
        controller = controller,
        warn_errors = TRUE
      )
      return(coro::generator(function() {
        repeat {
          chunk <- tryCatch(delegate(), error = codex_chat_error)
          if (coro::is_exhausted(chunk)) break
          coro::yield(chunk)
        }
      })())
    }
    delegate <- tryCatch(
      original_stream(..., stream = stream, controller = controller),
      error = codex_chat_error
    )

    coro::generator(function() {
      pieces <- character()
      repeat {
        chunk <- tryCatch(delegate(), error = codex_chat_error)
        if (coro::is_exhausted(chunk)) break
        pieces <- c(pieces, codex_stream_piece_for_history(chat, chunk))
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

  method_names <- c(
    "chat", "stream", "chat_structured", "chat_async", "stream_async",
    "chat_structured_async"
  )
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
  chat$stream_async <- patched_stream_async
  chat$chat_async <- patched_chat_async
  chat$chat_structured_async <- function(..., type, echo = "none", convert = TRUE) {
    codex_structured_async(chat, list(...), type = type, echo = echo, convert = convert)
  }
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
#' JSON-schema method and the same streamed-text repair. Registered ellmer
#' tools use the Codex Responses function-call protocol and are executed in a
#' complete loop until a final assistant response is produced. The returned
#' chat also supports `chat_async()`, `stream_async()` with ellmer's
#' sequential/concurrent tool modes and cancellation controller, and
#' `chat_structured_async()`.
#'
#' `$chat_structured()` intentionally follows ellmer's semantics and disables
#' registered tools for that request. Call `$chat()` first when tool-assisted
#' context is needed, then use `$chat_structured()` to extract structured data.
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
#'
#' weather_tool <- ellmer::tool(
#'   function(city) paste("Sunny in", city),
#'   name = "get_weather",
#'   description = "Get the current weather for a city.",
#'   arguments = list(city = ellmer::type_string())
#' )
#' chat$register_tool(weather_tool)
#' chat$chat("What is the weather in Montevideo?")
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

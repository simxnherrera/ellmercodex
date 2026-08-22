codex_echo <- function(echo, default = "none") {
  if (is.null(echo)) echo <- default
  # A missing argument arrives as the usual choices vector. Match the first
  # choice explicitly so errors remain package conditions rather than base
  # `match.arg()` errors.
  if (is.character(echo) && length(echo) > 1L &&
        all(echo %in% c("none", "output", "all"))) {
    echo <- echo[[1L]]
  }
  if (isTRUE(echo)) echo <- "output"
  if (isFALSE(echo)) echo <- "none"
  if (identical(echo, "text")) echo <- "output"
  if (!is.character(echo) || length(echo) != 1L || is.na(echo) ||
        !echo %in% c("none", "output", "all")) {
    rlang::abort(
      "`echo` must be one of \"none\", \"output\", or \"all\".",
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
  # Historical internal entry point retained for callers from 0.1.x. The
  # compatibility implementation itself is centralized in one module and
  # never replaces public Chat methods.
  codex_ellmer_compatibility()
  codex_install_private_submit_methods(chat)
}
#' Create a Codex chat backed by ellmer
#'
#' `chat_codex()` returns a normal ellmer `Chat` object configured for the
#' observed Codex subscription transport. It does not start browser
#' authentication. Call [codex_login()] explicitly first when no stored
#' credential is available; an existing credential is loaded and refreshed as
#' needed.
#'
#' The returned chat is the complete public `ellmer` 0.4.2 `Chat` object for
#' interactive, single-conversation operations, including ordinary and
#' structured chat, synchronous and asynchronous streaming, tool declarations
#' and multi-round execution, callbacks, cancellation, cloning, history, echo,
#' model/provider configuration, rich content, and response metadata. The
#' compatibility layer uses one version-gated provider/turn-submission seam
#' while leaving public Chat methods and ellmer lifecycle semantics intact.
#' The separate ellmer parallel/batch helpers are outside this stable core
#' contract and are explicitly blocked because their non-streaming request
#' model is incompatible with the Codex stream-only endpoint.
#'
#' `$chat_structured()` intentionally follows ellmer's semantics and disables
#' registered tools for that request. Call `$chat()` first when tool-assisted
#' context is needed, then use `$chat_structured()` to extract structured data.
#'
#' @param system_prompt Optional system prompt passed to ellmer.
#' @param model Optional Codex model name. If omitted, the package default is
#'   used; set the ELLMERCODEX_MODEL environment variable to choose a different
#'   default. Model availability is account- and workspace-specific, so
#'   [codex_models()] is the authoritative way to inspect available choices.
#' @param effort Optional Codex reasoning effort. It is forwarded through
#'   ellmer's `reasoning_effort` parameter and should be one of the
#'   values advertised by [codex_models()] for the selected model.
#' @param params Optional ellmer model parameters, usually created with
#'   `ellmer::params()`. A supplied `reasoning_effort` must agree with
#'   `effort`, when both are provided.
#'   Other ellmer-supported model parameters are passed through unchanged.
#' @param api_args Optional named list of additional Responses arguments passed
#'   through ellmer on every request. This is an advanced escape hatch for
#'   arguments accepted by the observed transport; unsupported arguments may
#'   be rejected by the remote service.
#' @param echo One of `"none"`, `"output"`, or `"all"`; controls whether `$chat()`
#'   prints the completed text. The compatibility wrapper accepts `TRUE`,
#'   `FALSE`, and `"text"` as aliases for `"output"`, `"none"`, and
#'   `"output"`, respectively.
#' @return An object inheriting from ellmer's `Chat` class.
#' The returned object retains ellmer's public Chat methods, history,
#' callbacks, registered tools, asynchronous methods, and R6 cloning behavior.
#'
#' @section Conditions:
#' Invalid arguments signal `codex_chat_argument_error`. Missing or
#' incompatible ellmer installations signal `codex_ellmer_missing` or
#' `codex_ellmer_compatibility_error`. Authentication failures found before
#' the Chat is constructed retain their package condition classes. Transport
#' and protocol errors retain their specific Codex/ellmer condition classes;
#' compatibility-shape failures use `codex_ellmer_compatibility_error`.
#' @section Side effects:
#' Constructing a chat reads the current process credential or this package's
#' credential store and may refresh an expired stored credential. It does not
#' open a browser. Requests occur only when the corresponding Chat method is
#' called; constructing a chat does not generate a response.
#' @seealso
#'   [codex_login()], [codex_account()], [codex_models()], [codex_logout()],
#'   and [ellmer::chat_openai()]
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
  echo = c("none", "output", "all"),
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
    api_args = api_args,
    echo = echo
  )
  codex_patch_chat(chat, default_echo = echo)
}

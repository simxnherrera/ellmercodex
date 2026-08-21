# Codex Responses tool calling on top of ellmer's public Chat object.

codex_ellmer_tool_compatibility <- function() {
  codex_ellmer_compatibility()

  # ellmer 0.4.2 does not export the provider JSON generic or the tool
  # invocation helper. There is no public API that can serialize a provider's
  # TypeObject and Responses history or invoke a ToolDef with ellmer's normal
  # conversion/rejection semantics. Keep this narrow seam in one check so a
  # later ellmer release can be adapted without spreading internal names.
  required_internals <- c(
    "as_json", "as_user_turn", "chat_body", "invoke_tool",
    "maybe_on_tool_request", "modify_list", "tool_string"
  )
  namespace <- asNamespace("ellmer")
  available_internals <- vapply(
    required_internals,
    function(name) exists(name, envir = namespace, inherits = FALSE),
    logical(1)
  )
  if (!all(available_internals)) {
    missing <- paste(required_internals[!available_internals], collapse = ", ")
    rlang::abort(
      paste0(
        "The installed ellmer version is missing tool compatibility symbols: ",
        missing, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  invisible(TRUE)
}

codex_ellmer_internal <- function(name) {
  codex_ellmer_tool_compatibility()
  utils::getFromNamespace(name, "ellmer")
}

codex_ellmer_chat_tool_compatibility <- function(chat) {
  codex_ellmer_tool_compatibility()
  private <- tryCatch(chat$.__enclos_env__$private, error = function(error) NULL)
  callback_names <- c(
    request = "callback_on_tool_request",
    result = "callback_on_tool_result"
  )
  available <- if (is.environment(private)) {
    vapply(
      callback_names,
      function(name) {
        if (!exists(name, envir = private, inherits = FALSE)) return(FALSE)
        manager <- get(name, envir = private, inherits = FALSE)
        is.environment(manager) && is.function(manager$invoke) &&
          is.function(manager$invoke_async)
      },
      logical(1)
    )
  } else {
    rep(FALSE, length(callback_names))
  }
  if (!all(available)) {
    missing <- paste(names(callback_names)[!available], collapse = ", ")
    rlang::abort(
      paste0(
        "The installed ellmer Chat is missing the tool callback compatibility seam: ",
        missing, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  private
}

codex_tool_event_is_function <- function(event) {
  if (!is.list(event)) return(FALSE)
  item <- event$item
  if (!is.list(item)) return(FALSE)
  type <- item$type
  is.character(type) && length(type) == 1L && !is.na(type) &&
    (identical(type, "function_call") ||
       grepl("function_call|tool_call", type, fixed = FALSE))
}

codex_tool_type_is_function_event <- function(type) {
  is.character(type) && length(type) == 1L && !is.na(type) &&
    grepl("function_call|tool_call", type, fixed = FALSE)
}

codex_tool_event_type <- function(event) {
  if (!is.list(event)) return(NULL)
  type <- event$type
  if (is.character(type) && length(type) == 1L && !is.na(type) && nzchar(type)) {
    type
  } else {
    NULL
  }
}

codex_tool_scalar <- function(value) {
  if (is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)) {
    value
  } else {
    NULL
  }
}

codex_tool_event_ids <- function(event, item = NULL) {
  item <- item %||% if (is.list(event)) event$item else NULL
  values <- list(
    item_id = if (is.list(event)) event$item_id else NULL,
    output_item_id = if (is.list(event)) event$output_item_id else NULL,
    call_id = if (is.list(event)) event$call_id else NULL,
    output_index = if (is.list(event)) event$output_index else NULL,
    item_item_id = if (is.list(item)) item$id else NULL,
    item_call_id = if (is.list(item)) item$call_id else NULL,
    item_output_index = if (is.list(item)) item$output_index else NULL
  )
  values <- values[!vapply(values, is.null, logical(1))]
  unname(values)
}

codex_tool_id_key <- function(value) {
  if (is.numeric(value) && length(value) == 1L && is.finite(value)) {
    return(paste0("index:", format(value, scientific = FALSE, trim = TRUE)))
  }
  value <- codex_tool_scalar(value)
  if (is.null(value)) NULL else paste0("value:", value)
}

codex_tool_parse_arguments <- function(call) {
  if (!is.null(call$arguments_value)) {
    if (!is.list(call$arguments_value)) {
      codex_sse_protocol_error(
        "The Codex function-call arguments were not a JSON object."
      )
    }
    return(call$arguments_value)
  }

  raw <- call$arguments_text
  if (is.null(raw) || (is.character(raw) && length(raw) == 1L && !nzchar(raw))) {
    return(list())
  }
  if (!is.character(raw) || length(raw) != 1L || is.na(raw)) {
    codex_sse_protocol_error(
      "The Codex function-call arguments were not valid text."
    )
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(raw, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (!is.list(parsed)) {
    codex_sse_protocol_error(
      "The Codex function-call arguments were not valid JSON."
    )
  }
  parsed
}

codex_tool_parse_response <- function(events) {
  if (!is.list(events)) {
    codex_sse_protocol_error("The Codex SSE event sequence was malformed.")
  }

  state <- new.env(parent = emptyenv())
  state$calls <- list()
  call_map <- new.env(parent = emptyenv())
  state$event_order <- list()
  state$text_pieces <- character()
  state$text_segments <- list()
  state$text_delta_seen <- FALSE
  text_done <- character()
  terminal <- NULL
  terminal_type <- NULL

  call_map_get <- function(value) {
    key <- codex_tool_id_key(value)
    if (is.null(key) || !exists(key, envir = call_map, inherits = FALSE)) {
      return(NULL)
    }
    get(key, envir = call_map, inherits = FALSE)
  }

  call_map_set <- function(value, index) {
    key <- codex_tool_id_key(value)
    if (!is.null(key)) assign(key, index, envir = call_map)
  }

  call_find <- function(event, item = NULL) {
    ids <- codex_tool_event_ids(event, item = item)
    for (value in ids) {
      found <- call_map_get(value)
      if (!is.null(found)) return(found)
    }
    NULL
  }

  call_add <- function(event = list(), item = NULL) {
    index <- call_find(event, item = item)
    if (is.null(index)) {
      index <- length(state$calls) + 1L
      state$calls[[index]] <- list(
        id = NULL,
        name = NULL,
        arguments_text = NULL,
        arguments_value = NULL,
        item_id = NULL,
        output_index = NULL
      )
    }

    call <- state$calls[[index]]
    item <- item %||% if (is.list(event)) event$item else NULL
    item_id <- if (is.list(event)) event$item_id else NULL
    if (is.null(item_id) && is.list(event)) item_id <- event$output_item_id
    if (is.null(item_id) && is.list(item)) item_id <- item$id
    call_id <- if (is.list(event)) event$call_id else NULL
    if (is.null(call_id) && is.list(item)) call_id <- item$call_id
    name <- if (is.list(event)) event$name else NULL
    if (is.null(name) && is.list(item)) name <- item$name
    output_index <- if (is.list(event)) event$output_index else NULL
    if (is.null(output_index) && is.list(item)) output_index <- item$output_index

    if (!is.null(call_id)) call$id <- codex_tool_scalar(call_id)
    if (!is.null(name)) call$name <- codex_tool_scalar(name)
    if (!is.null(item_id)) call$item_id <- codex_tool_scalar(item_id)
    if (!is.null(output_index)) call$output_index <- output_index

    arguments <- if (is.list(event)) event$arguments else NULL
    if (is.null(arguments) && is.list(item)) arguments <- item$arguments
    if (is.list(arguments)) {
      call$arguments_value <- arguments
      call$arguments_text <- NULL
    } else if (is.character(arguments) && length(arguments) == 1L && !is.na(arguments)) {
      call$arguments_text <- arguments
      call$arguments_value <- NULL
    }

    state$calls[[index]] <- call
    for (value in codex_tool_event_ids(event, item = item)) {
      call_map_set(value, index)
    }
    index
  }

  call_append_arguments <- function(event) {
    index <- call_find(event)
    if (is.null(index)) index <- call_add(event)
    call <- state$calls[[index]]
    delta <- event$delta
    if (!is.character(delta) || length(delta) != 1L || is.na(delta)) {
      codex_sse_protocol_error(
        "The Codex function-call argument delta was not text."
      )
    }
    call$arguments_text <- paste0(call$arguments_text %||% "", delta)
    call$arguments_value <- NULL
    state$calls[[index]] <- call
    index
  }

  call_set_arguments <- function(event) {
    index <- call_find(event)
    if (is.null(index)) index <- call_add(event)
    call <- state$calls[[index]]
    arguments <- event$arguments
    if (is.list(arguments)) {
      call$arguments_value <- arguments
      call$arguments_text <- NULL
    } else if (is.character(arguments) && length(arguments) == 1L && !is.na(arguments)) {
      call$arguments_text <- arguments
      call$arguments_value <- NULL
    } else {
      codex_sse_protocol_error(
        "The Codex completed function-call arguments were malformed."
      )
    }
    state$calls[[index]] <- call
    index
  }

  append_event_order <- function(value) {
    if (length(state$event_order) == 0L || !identical(
      state$event_order[[length(state$event_order)]], value
    )) {
      state$event_order[[length(state$event_order) + 1L]] <- value
    }
  }

  append_text <- function(value, from_delta = FALSE) {
    if (is.null(value)) return(invisible())
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      codex_sse_protocol_error("The Codex output text delta was malformed.")
    }
    if (!nzchar(value)) return(invisible())
    if (
      length(state$event_order) > 0L &&
        identical(state$event_order[[length(state$event_order)]], "text")
    ) {
      index <- length(state$text_segments)
      state$text_segments[[index]] <- paste0(state$text_segments[[index]], value)
    } else {
      state$text_segments[[length(state$text_segments) + 1L]] <- value
    }
    state$text_pieces <- c(state$text_pieces, value)
    if (isTRUE(from_delta)) state$text_delta_seen <- TRUE
    append_event_order("text")
    invisible()
  }

  for (event in events) {
    if (!is.list(event)) {
      codex_sse_protocol_error("The Codex SSE event sequence was malformed.")
    }
    type <- codex_tool_event_type(event)
    if (is.null(type)) next

    if (identical(type, "response.output_text.delta")) {
      append_text(event$delta, from_delta = TRUE)
    } else if (identical(type, "response.output_text.done")) {
      if (!is.null(event$text)) {
        if (!is.character(event$text) || length(event$text) != 1L || is.na(event$text)) {
          codex_sse_protocol_error("The completed Codex output text was malformed.")
        }
        text_done <- c(text_done, event$text)
      }
    } else if (identical(type, "response.output_item.added")) {
      if (codex_tool_event_is_function(event)) {
        index <- call_add(event, item = event$item)
        append_event_order(paste0("call:", index))
      }
    } else if (identical(type, "response.output_item.done")) {
      if (codex_tool_event_is_function(event)) {
        index <- call_add(event, item = event$item)
        append_event_order(paste0("call:", index))
      }
    } else if (identical(type, "response.function_call_arguments.delta")) {
      index <- call_append_arguments(event)
      append_event_order(paste0("call:", index))
    } else if (identical(type, "response.function_call_arguments.done")) {
      index <- call_set_arguments(event)
      append_event_order(paste0("call:", index))
    } else if (type %in% c("response.completed", "response.done", "response.incomplete")) {
      if (is.null(terminal_type)) {
        terminal <- event$response
        if (!is.list(terminal) && is.list(event$output)) terminal <- event
        terminal_type <- type
      }
    } else if (identical(type, "response.failed")) {
      codex_sse_error(event, "Codex generation failed.")
    } else if (identical(type, "error")) {
      codex_sse_error(event)
    } else if (codex_tool_type_is_function_event(type)) {
      codex_sse_protocol_error(
        paste0("The Codex emitted an unhandled tool event: ", type, ".")
      )
    }
    # Non-tool metadata/progress events are intentionally ignorable.
  }

  if (is.null(terminal_type)) {
    codex_sse_protocol_error(
      "The Codex SSE stream ended without a terminal response event."
    )
  }
  incomplete <- identical(terminal_type, "response.incomplete") ||
    (is.list(terminal) && identical(terminal$status, "incomplete"))
  if (incomplete) {
    rlang::abort("The Codex response was incomplete.", class = "codex_incomplete_error")
  }

  terminal_order <- list()
  terminal_text <- character()
  if (is.list(terminal) && is.list(terminal$output)) {
    for (item in terminal$output) {
      if (!is.list(item)) next
      if (codex_tool_event_is_function(list(item = item))) {
        index <- call_add(item, item = item)
        terminal_order[[length(terminal_order) + 1L]] <- paste0("call:", index)
      } else if (identical(item$type, "message") && is.list(item$content)) {
        message_text <- vapply(
          item$content,
          function(content) {
            if (
              is.list(content) &&
                identical(content$type, "output_text") &&
                is.character(content$text) && length(content$text) == 1L
            ) {
              content$text
            } else {
              ""
            }
          },
          character(1)
        )
        message_text <- paste0(message_text, collapse = "")
        if (nzchar(message_text)) {
          terminal_text <- c(terminal_text, message_text)
          terminal_order[[length(terminal_order) + 1L]] <- "text"
        }
      }
    }
  }

  calls <- state$calls
  event_order <- state$event_order
  text_pieces <- state$text_pieces
  text_segments <- state$text_segments
  text_delta_seen <- state$text_delta_seen

  if (!text_delta_seen && length(text_pieces) == 0L) {
    if (length(terminal_text) > 0L) {
      text_pieces <- terminal_text
      text_segments <- as.list(terminal_text)
    } else if (length(text_done) > 0L) {
      text_pieces <- text_done
      text_segments <- as.list(text_done)
    } else if (
      is.list(terminal) &&
        is.character(terminal$output_text) &&
        length(terminal$output_text) == 1L && !is.na(terminal$output_text)
    ) {
      text_pieces <- terminal$output_text
      text_segments <- list(terminal$output_text)
    }
  }

  event_has_text <- any(vapply(event_order, identical, logical(1), "text"))
  if (length(terminal_order) > 0L && event_has_text) {
    # Deltas preserve the order in which text and calls were emitted. The
    # terminal response is authoritative for any item omitted from the
    # stream, but must not move text across a call when the terminal output is
    # incomplete (which the Codex subscription endpoint has been observed to
    # do).
    order <- event_order
    for (entry in unique(unlist(terminal_order, use.names = FALSE))) {
      present <- sum(vapply(order, identical, logical(1), entry))
      required <- sum(vapply(terminal_order, identical, logical(1), entry))
      while (present < required) {
        order[[length(order) + 1L]] <- entry
        present <- present + 1L
      }
    }
  } else if (length(terminal_order) > 0L) {
    order <- terminal_order
  } else {
    order <- event_order
    if (length(order) == 0L && length(text_pieces) > 0L) order <- list("text")
  }
  if (
    length(text_segments) > 0L &&
      !any(vapply(order, identical, logical(1), "text"))
  ) {
    order[[length(order) + 1L]] <- "text"
  }

  used_calls <- integer()
  ordered_calls <- integer()
  for (entry in order) {
    if (startsWith(entry, "call:")) {
      index <- suppressWarnings(as.integer(sub("^call:", "", entry)))
      if (
        is.finite(index) && index >= 1L && index <= length(calls) &&
          !index %in% used_calls
      ) {
        ordered_calls <- c(ordered_calls, index)
        used_calls <- c(used_calls, index)
      }
    }
  }
  if (length(calls) > 0L) {
    ordered_calls <- c(ordered_calls, setdiff(seq_along(calls), used_calls))
  }

  call_position <- integer(length(calls))
  call_position[ordered_calls] <- seq_along(ordered_calls)
  normalized_order <- lapply(order, function(entry) {
    if (!startsWith(entry, "call:")) return(entry)
    index <- suppressWarnings(as.integer(sub("^call:", "", entry)))
    if (
      !is.finite(index) || index < 1L || index > length(call_position) ||
        call_position[[index]] == 0L
    ) {
      entry
    } else {
      paste0("call:", call_position[[index]])
    }
  })

  parsed_calls <- lapply(ordered_calls, function(index) {
    call <- calls[[index]]
    id <- codex_tool_scalar(call$id)
    name <- codex_tool_scalar(call$name)
    if (is.null(id) || is.null(name)) {
      codex_sse_protocol_error(
        "The Codex function-call event did not include a call ID and name."
      )
    }
    list(
      id = id,
      name = name,
      arguments = codex_tool_parse_arguments(call),
      arguments_text = call$arguments_text,
      item_id = call$item_id,
      output_index = call$output_index
    )
  })

  text <- paste0(text_pieces, collapse = "")
  if (length(parsed_calls) == 0L && !nzchar(text)) {
    codex_sse_protocol_error(
      "The terminal Codex response contained no text or tool call."
    )
  }

  list(
    text = text,
    text_pieces = text_pieces,
    text_segments = text_segments,
    calls = parsed_calls,
    order = normalized_order,
    response = terminal,
    terminal_type = terminal_type,
    events = events
  )
}

codex_parse_sse_tool_response <- function(events) {
  codex_tool_parse_response(events)
}

codex_tool_response_from_body <- function(body, content_type = NA_character_) {
  if (!is.character(body) || length(body) != 1L || is.na(body)) {
    rlang::abort(
      "The Codex response body could not be read.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }

  if (codex_is_sse_body(content_type, body)) {
    return(codex_parse_sse_tool_response(codex_parse_sse(body)))
  }

  value <- tryCatch(
    jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (!is.list(value)) {
    rlang::abort(
      "The Codex response was not valid JSON or SSE.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }
  codex_parse_sse_tool_response(list(list(
    type = "response.completed",
    response = value
  )))
}

codex_tool_body <- function(chat, turns) {
  provider <- chat$get_provider()
  chat_body <- codex_ellmer_internal("chat_body")
  body <- chat_body(
    provider = provider,
    stream = TRUE,
    turns = turns,
    tools = unname(chat$get_tools()),
    type = NULL
  )

  extra_args <- provider@extra_args
  if (length(extra_args) > 0L) {
    modify_list <- utils::getFromNamespace("modify_list", "ellmer")
    body <- modify_list(body, extra_args)
  }
  # The subscription transport is stream-only. Preserve ellmer's api_args,
  # except that a caller cannot turn off the event stream needed for tool
  # argument deltas and terminal response assembly.
  body$stream <- TRUE
  body
}

codex_tool_request <- function(chat, body) {
  provider <- chat$get_provider()
  token <- tryCatch(
    provider@credentials(),
    error = function(error) NULL
  )
  if (!is.character(token) || length(token) != 1L || is.na(token) || !nzchar(token)) {
    rlang::abort(
      "The Codex credential callback did not return an access token.",
      class = "codex_authentication_error",
      parent = NULL
    )
  }

  headers <- c(
    Authorization = paste0("Bearer ", token),
    provider@extra_headers
  )
  request <- httr2::request(codex_responses_url()) |>
    httr2::req_headers(!!!headers) |>
    httr2::req_body_json(body, auto_unbox = TRUE) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(response) FALSE)

  response <- tryCatch(
    httr2::req_perform(request),
    error = function(error) {
      rlang::abort(
        "The Codex request failed because of an ordinary network error.",
        class = "codex_network_error",
        parent = NULL
      )
    }
  )
  status <- tryCatch(httr2::resp_status(response), error = function(error) NA_integer_)
  if (is.na(status) || status < 200L || status >= 300L) {
    codex_abort_response(response)
  }

  content_type <- tryCatch(
    httr2::resp_content_type(response),
    error = function(error) NA_character_
  )
  response_body <- tryCatch(
    httr2::resp_body_string(response),
    error = function(error) NULL
  )
  codex_tool_response_from_body(response_body, content_type = content_type)
}

codex_tool_make_assistant_turn <- function(parsed, tools) {
  contents <- list()
  text_segments <- parsed$text_segments
  if (!is.list(text_segments)) text_segments <- list()
  if (length(text_segments) == 0L && nzchar(parsed$text)) {
    text_segments <- list(parsed$text)
  }
  text_index <- 0L
  requests <- list()
  request_indices <- integer()

  for (entry in parsed$order) {
    if (identical(entry, "text") && text_index < length(text_segments)) {
      text_index <- text_index + 1L
      contents[[length(contents) + 1L]] <- ellmer::ContentText(
        text_segments[[text_index]]
      )
    } else if (startsWith(entry, "call:")) {
      index <- suppressWarnings(as.integer(sub("^call:", "", entry)))
      if (
        is.finite(index) && index >= 1L && index <= length(parsed$calls) &&
          !index %in% request_indices
      ) {
        call <- parsed$calls[[index]]
        tool <- tools[[call$name]]
        if (is.null(tool)) {
          codex_sse_protocol_error(
            paste0("Codex requested the unregistered tool `", call$name, "`.")
          )
        }
        extra <- Filter(
          Negate(is.null),
          list(item_id = call$item_id, output_index = call$output_index)
        )
        request <- ellmer::ContentToolRequest(
          id = call$id,
          name = call$name,
          arguments = call$arguments,
          tool = tool,
          extra = extra
        )
        contents[[length(contents) + 1L]] <- request
        requests[[length(requests) + 1L]] <- request
        request_indices <- c(request_indices, index)
      }
    }
  }

  if (length(requests) != length(parsed$calls)) {
    codex_sse_protocol_error(
      "The Codex tool-call response could not be represented in ellmer history."
    )
  }

  if (text_index < length(text_segments)) {
    contents <- c(
      contents,
      lapply(
        text_segments[seq.int(text_index + 1L, length(text_segments))],
        ellmer::ContentText
      )
    )
  }

  output <- parsed$response
  if (!is.list(output)) output <- list(status = "completed")
  output_items <- if (is.list(output$output)) output$output else list()
  has_function_items <- any(vapply(
    output_items,
    function(item) codex_tool_event_is_function(list(item = item)),
    logical(1)
  ))
  if (length(parsed$calls) > 0L && !has_function_items) {
    output_items <- c(
      lapply(parsed$calls, function(call) {
        Filter(
          Negate(is.null),
          list(
            type = "function_call",
            id = call$item_id,
            call_id = call$id,
            name = call$name,
            arguments = call$arguments_text %||% jsonlite::toJSON(
              call$arguments,
              auto_unbox = TRUE,
              null = "null"
            )
          )
        )
      }),
      output_items
    )
  }
  has_output_text <- any(vapply(
    output_items,
    function(item) {
      is.list(item) && identical(item$type, "message") &&
        is.list(item$content) && any(vapply(
        item$content,
        function(content) {
          is.list(content) && identical(content$type, "output_text")
        },
        logical(1)
      ))
    },
    logical(1)
  ))
  if (nzchar(parsed$text) && !has_output_text) {
    output_items <- c(
      output_items,
      list(list(
        type = "message",
        content = list(list(type = "output_text", text = parsed$text))
      ))
    )
  }
  output$output <- output_items

  assistant <- ellmer::AssistantTurn(
    contents = contents,
    json = output,
    finish_reason = if (length(requests) > 0L) "tool_use" else "success"
  )
  list(turn = assistant, requests = requests)
}

codex_tool_append_turn <- function(chat, turn) {
  turns <- chat$get_turns(include_system_prompt = TRUE)
  chat$set_turns(c(turns, list(turn)))
  invisible(turn)
}

codex_tool_callbacks <- function(chat, which = c("request", "result")) {
  # ellmer exposes registration methods but not a public way to invoke the
  # registered callbacks. This is the one narrow Chat-private seam used to
  # preserve normal on_tool_request()/on_tool_result() behavior.
  which <- match.arg(which)
  private <- codex_ellmer_chat_tool_compatibility(chat)
  name <- if (identical(which, "request")) {
    "callback_on_tool_request"
  } else {
    "callback_on_tool_result"
  }
  callback_manager <- get(name, envir = private, inherits = FALSE)
  callback_manager$invoke
}

codex_tool_execute <- function(chat, request) {
  invoke_tool <- codex_ellmer_internal("invoke_tool")
  maybe_on_tool_request <- codex_ellmer_internal("maybe_on_tool_request")
  on_request <- codex_tool_callbacks(chat, "request")
  rejected <- maybe_on_tool_request(request, on_tool_request = on_request)
  if (!is.null(rejected)) {
    on_result <- codex_tool_callbacks(chat, "result")
    on_result(rejected)
    return(rejected)
  }

  result <- invoke_tool(request)
  value <- tryCatch(result@value, error = function(error) NULL)
  if (inherits(value, "promise")) {
    rlang::abort(
      paste(
        "The legacy buffered tool parser cannot execute an async tool.",
        "The public Chat path uses ellmer's asynchronous methods instead."
      ),
      class = "tool_async_error",
      parent = NULL
    )
  }
  on_result <- codex_tool_callbacks(chat, "result")
  on_result(result)
  result
}

codex_tool_result_error <- function(result) {
  error <- tryCatch(result@error, error = function(condition) NULL)
  !is.null(error)
}

codex_tool_warn_errors <- function(results) {
  failed <- Filter(codex_tool_result_error, results)
  if (length(failed) == 0L) return(invisible())
  details <- vapply(
    failed[seq_len(min(3L, length(failed)))],
    function(result) {
      request <- result@request
      error <- result@error
      detail <- if (inherits(error, "condition")) conditionMessage(error) else as.character(error)
      sprintf("[%s (%s)]: %s", request@name, request@id, detail)
    },
    character(1)
  )
  message <- paste0(
    "Failed to evaluate ", length(failed), " tool call",
    if (length(failed) == 1L) "" else "s", ". ",
    paste(details, collapse = "; ")
  )
  rlang::warn(message, class = "ellmer_tool_failure")
  invisible()
}

codex_tool_has_tools <- function(chat) {
  tools <- tryCatch(chat$get_tools(), error = function(error) NULL)
  is.list(tools) && length(tools) > 0L
}

codex_tool_stream <- function(
  chat,
  dots,
  stream = c("text", "content"),
  controller = NULL,
  warn_errors = TRUE
) {
  stream <- match.arg(stream)
  if (is.null(controller)) controller <- ellmer::stream_controller()

  coro::generator(function() {
    tool_errors <- list()
    on.exit(
      if (isTRUE(warn_errors)) codex_tool_warn_errors(tool_errors),
      add = TRUE
    )

    user_turn <- codex_ellmer_internal("as_user_turn")(
      dots,
      check_empty = TRUE
    )
    codex_tool_append_turn(chat, user_turn)

    steps <- 0L
    repeat {
      if (isTRUE(controller$cancelled)) break
      steps <- steps + 1L
      if (steps > 100L) {
        rlang::abort(
          "The Codex tool loop exceeded 100 rounds.",
          class = "codex_protocol_changed_error",
          parent = NULL
        )
      }

      turns <- chat$get_turns(include_system_prompt = TRUE)
      parsed <- codex_tool_request(chat, codex_tool_body(chat, turns))
      assistant <- codex_tool_make_assistant_turn(parsed, chat$get_tools())
      codex_tool_append_turn(chat, assistant$turn)

      if (length(parsed$text_pieces) > 0L) {
        pieces <- parsed$text_pieces
        if (stream == "content") {
          for (piece in pieces) coro::yield(ellmer::ContentText(piece))
        } else {
          for (piece in pieces) coro::yield(piece)
        }
      }

      if (length(assistant$requests) == 0L) break

      results <- list()
      for (request in assistant$requests) {
        if (stream == "content") coro::yield(request)
        result <- codex_tool_execute(chat, request)
        if (codex_tool_result_error(result)) {
          tool_errors[[length(tool_errors) + 1L]] <- result
        }
        if (stream == "content") coro::yield(result)
        results[[length(results) + 1L]] <- result
      }

      if (length(results) == 0L) {
        rlang::abort(
          "The Codex returned tool calls but no tool results could be created.",
          class = "codex_protocol_changed_error",
          parent = NULL
        )
      }
      codex_tool_append_turn(chat, ellmer::UserTurn(results))
    }
  })()
}

codex_tool_chat <- function(chat, dots, echo = "none") {
  echo <- codex_echo(echo)
  tryCatch(
    coro::collect(codex_tool_stream(
      chat,
      dots,
      stream = "text",
      warn_errors = identical(echo, "none")
    )),
    error = codex_chat_error
  )

  assistant <- tryCatch(chat$last_turn(role = "assistant"), error = function(error) NULL)
  text <- if (is.null(assistant)) "" else assistant@text
  if (!is.character(text) || length(text) != 1L || is.na(text)) text <- ""
  value <- structure(text, class = "ellmer_output")
  if (identical(echo, "output")) {
    cat(text, "\n", sep = "")
    invisible(value)
  } else {
    value
  }
}

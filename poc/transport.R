codex_request_body <- function(prompt, model = codex_default_model()) {
  if (!is.character(prompt) || length(prompt) != 1L || !nzchar(prompt)) {
    rlang::abort("`prompt` must be one non-empty string.", class = "codex_request_error")
  }
  if (!is.character(model) || length(model) != 1L || !nzchar(model)) {
    rlang::abort("`model` must be one non-empty string.", class = "codex_request_error")
  }

  list(
    model = model,
    instructions = "You are a helpful assistant. Follow the user's output instructions exactly.",
    input = list(list(
      role = "user",
      content = list(list(type = "input_text", text = prompt))
    )),
    store = FALSE,
    stream = TRUE
  )
}

codex_sanitize_error_detail <- function(detail) {
  if (!is.character(detail) || length(detail) != 1L) return(NULL)
  detail <- codex_redact(detail)
  detail <- gsub("https?://[^[:space:]]+", "<redacted-url>", detail, perl = TRUE)
  detail <- gsub(
    "[[:alnum:]_.+-]+@[[:alnum:].-]+",
    "<redacted-email>", detail, perl = TRUE
  )
  detail <- gsub("[A-Za-z0-9_-]{20,}", "<redacted-value>", detail, perl = TRUE)
  substr(detail, 1L, 300L)
}

codex_error_detail_value <- function(value) {
  if (!is.list(value)) return(NULL)
  if (is.list(value$error)) {
    detail <- value$error$message %||% value$error$code %||% value$error$type
  } else {
    detail <- value$detail %||% value$error
  }
  codex_sanitize_error_detail(detail)
}

codex_error_detail <- function(response) {
  value <- tryCatch(httr2::resp_body_json(response, simplifyVector = TRUE),
    error = function(error) NULL
  )
  codex_error_detail_value(value)
}

codex_abort_response <- function(response) {
  status <- httr2::resp_status(response)
  detail <- codex_error_detail(response)
  suffix <- if (is.null(detail) || !nzchar(detail)) "" else paste0(" ", detail)

  if (status %in% c(401L, 403L)) {
    message <- paste0("Codex authentication or subscription authorization failed.", suffix)
    class <- "codex_authentication_error"
  } else if (status == 429L) {
    message <- paste0("Codex subscription or rate limit reached.", suffix)
    class <- "codex_rate_limit_error"
  } else if (status == 404L) {
    message <- paste0("The Codex model or transport endpoint is unavailable.", suffix)
    class <- "codex_model_unavailable_error"
  } else if (status %in% c(400L, 409L, 422L)) {
    message <- paste0("The Codex transport rejected the request.", suffix)
    class <- "codex_malformed_request_error"
  } else if (status >= 500L) {
    message <- paste0("The Codex service failed while handling the request.", suffix)
    class <- "codex_server_error"
  } else {
    message <- sprintf("The Codex transport returned HTTP %d.%s", status, suffix)
    class <- "codex_protocol_error"
  }
  rlang::abort(message, class = class)
}

codex_request <- function(prompt, auth, model = codex_default_model()) {
  headers <- codex_request_headers(auth)
  request <- httr2::request(codex_responses_url()) |>
    httr2::req_headers(!!!headers) |>
    httr2::req_body_json(codex_request_body(prompt, model), auto_unbox = TRUE) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(response) FALSE)

  response <- tryCatch(httr2::req_perform(request), error = function(error) {
    rlang::abort(
      "The Codex request failed because of an ordinary network error.",
      class = "codex_network_error"
    )
  })
  status <- httr2::resp_status(response)
  if (status < 200L || status >= 300L) codex_abort_response(response)
  response
}

codex_parse_response <- function(value) {
  if (!is.list(value) || !is.list(value$output)) {
    rlang::abort(
      "The Codex response did not match the expected Responses JSON shape.",
      class = "codex_protocol_changed_error"
    )
  }

  pieces <- character()
  for (item in value$output) {
    if (!is.list(item) || !identical(item$type, "message") || !is.list(item$content)) next
    for (content in item$content) {
      if (is.list(content) && identical(content$type, "output_text") && is.character(content$text)) {
        pieces <- c(pieces, content$text)
      }
    }
  }
  if (length(pieces) == 0L) {
    rlang::abort(
      "The Codex response contained no output text; the upstream protocol may have changed.",
      class = "codex_protocol_changed_error"
    )
  }
  paste0(pieces, collapse = "")
}

codex_parse_sse <- function(value) {
  if (!is.character(value) || length(value) != 1L) {
    rlang::abort(
      "The Codex SSE response was not text.",
      class = "codex_protocol_changed_error"
    )
  }

  value <- gsub("\r\n?", "\n", value)
  blocks <- strsplit(value, "\n\n+", perl = TRUE)[[1L]]
  events <- list()

  for (block in blocks) {
    lines <- strsplit(block, "\n", fixed = TRUE)[[1L]]
    data_lines <- lines[startsWith(lines, "data:")]
    if (length(data_lines) == 0L) next
    data <- sub("^data:[ ]?", "", data_lines)
    data <- paste(data, collapse = "\n")
    if (!nzchar(data) || identical(data, "[DONE]")) next

    event <- tryCatch(
      jsonlite::fromJSON(data, simplifyVector = FALSE),
      error = function(error) NULL
    )
    if (!is.list(event)) {
      rlang::abort(
        "The Codex SSE stream contained invalid JSON.",
        class = "codex_protocol_changed_error"
      )
    }
    events[[length(events) + 1L]] <- event
  }
  events
}

codex_sse_error <- function(event, message) {
  error <- event$error
  if (!is.list(error) && is.list(event$response)) error <- event$response$error
  detail <- if (is.list(error)) error$message %||% error$code %||% error$type else error
  detail <- codex_sanitize_error_detail(detail)
  if (!is.null(detail) && nzchar(detail)) message <- paste(message, detail)
  rlang::abort(message, class = "codex_generation_error")
}

codex_parse_sse_response <- function(events) {
  if (!is.list(events)) {
    rlang::abort(
      "The Codex SSE event sequence was malformed.",
      class = "codex_protocol_changed_error"
    )
  }

  pieces <- character()
  done_text <- character()
  terminal <- NULL
  terminal_type <- NULL

  for (event in events) {
    type <- event$type
    if (!is.character(type) || length(type) != 1L) next

    if (identical(type, "response.output_text.delta") &&
      is.character(event$delta) && length(event$delta) == 1L) {
      pieces <- c(pieces, event$delta)
    } else if (identical(type, "response.output_text.done") &&
      is.character(event$text) && length(event$text) == 1L) {
      done_text <- c(done_text, event$text)
    } else if (type %in% c("response.completed", "response.done", "response.incomplete")) {
      terminal <- event$response
      terminal_type <- type
      break
    } else if (identical(type, "response.failed")) {
      codex_sse_error(event, "Codex generation failed.")
    } else if (identical(type, "error")) {
      codex_sse_error(event, "The Codex stream returned an error.")
    }
  }

  if (is.null(terminal_type)) {
    rlang::abort(
      "The Codex SSE stream ended without a terminal response event.",
      class = "codex_protocol_changed_error"
    )
  }
  if (identical(terminal_type, "response.incomplete") ||
    identical(terminal$status, "incomplete")) {
    rlang::abort(
      "The Codex response was incomplete.",
      class = "codex_incomplete_error"
    )
  }

  if (length(pieces) > 0L) return(paste0(pieces, collapse = ""))
  if (length(done_text) > 0L) return(paste0(done_text, collapse = ""))
  if (is.list(terminal)) return(codex_parse_response(terminal))

  rlang::abort(
    "The terminal Codex SSE event contained no response payload.",
    class = "codex_protocol_changed_error"
  )
}

codex_is_sse_body <- function(content_type, body) {
  declared_sse <- is.character(content_type) && length(content_type) == 1L &&
    !is.na(content_type) && identical(content_type, "text/event-stream")
  sniffed_sse <- is.character(body) && length(body) == 1L &&
    grepl("^(event:|data:)", body)
  declared_sse || sniffed_sse
}

codex_generate <- function(prompt, model = codex_default_model(), auth = NULL) {
  explicit_auth <- !is.null(auth)
  if (is.null(auth)) auth <- codex_auth()
  if (codex_token_expired(auth)) auth <- codex_refresh(auth, persist = !explicit_auth)
  response <- codex_request(prompt, auth = auth, model = model)

  content_type <- httr2::resp_content_type(response)
  body <- tryCatch(httr2::resp_body_string(response), error = function(error) NULL)
  if (is.null(body)) {
    rlang::abort(
      "The Codex response body could not be read.",
      class = "codex_protocol_changed_error"
    )
  }
  if (codex_is_sse_body(content_type, body)) {
    return(codex_parse_sse_response(codex_parse_sse(body)))
  }

  value <- tryCatch(jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (is.null(value)) {
    rlang::abort(
      "The Codex response was not valid JSON; the upstream protocol may require streaming or may have changed.",
      class = "codex_protocol_changed_error"
    )
  }
  codex_parse_response(value)
}

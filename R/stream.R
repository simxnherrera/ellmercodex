# Server-sent event framing and Responses event interpretation.

codex_stream_abort <- function(message, class = "codex_protocol_changed_error") {
  rlang::abort(message, class = class)
}

codex_stream_sanitize <- function(detail) {
  if (!is.character(detail) || length(detail) != 1L || is.na(detail)) {
    return(NULL)
  }

  detail <- as.character(detail)
  # Keep diagnostics useful without allowing credentials, authorization codes,
  # account IDs, URLs, or arbitrary JWT-like values into an error condition.
  detail <- gsub(
    "Bearer[[:space:]]+[^[:space:]]+",
    "Bearer <redacted>",
    detail,
    ignore.case = TRUE,
    perl = TRUE
  )
  detail <- gsub(
    "([?&](?:code|state|code_verifier)=)[^&#[:space:]]+",
    "\\1<redacted>",
    detail,
    ignore.case = TRUE,
    perl = TRUE
  )
  detail <- gsub(
    paste0(
      "(access_token|refresh_token|id_token|account_id|",
      "chatgpt[-_]account[-_]id)([[:space:]]*[:=][[:space:]]*)",
      "[^,}[:space:]]+"
    ),
    "\\1\\2<redacted>",
    detail,
    ignore.case = TRUE,
    perl = TRUE
  )
  detail <- gsub(
    "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
    "<redacted-jwt>",
    detail,
    perl = TRUE
  )
  detail <- gsub("https?://[^[:space:]]+", "<redacted-url>", detail, perl = TRUE)
  detail <- gsub(
    "[[:alnum:]_.+-]+@[[:alnum:].-]+",
    "<redacted-email>",
    detail,
    perl = TRUE
  )
  detail <- gsub("[A-Za-z0-9_-]{20,}", "<redacted-value>", detail, perl = TRUE)
  substr(detail, 1L, 300L)
}

# Keep the historical helper name used by the PoC and by transport diagnostics.
codex_sanitize_error_detail <- codex_stream_sanitize

codex_sse_event_type <- function(event) {
  if (!is.list(event)) {
    return(NULL)
  }
  type <- event$type
  if (is.character(type) && length(type) == 1L && !is.na(type) && nzchar(type)) {
    type
  } else {
    NULL
  }
}

codex_sse_protocol_error <- function(message) {
  codex_stream_abort(message, "codex_protocol_changed_error")
}

codex_sse_parse_block <- function(block, max_event_bytes) {
  if (nchar(block, type = "bytes") > max_event_bytes) {
    codex_sse_protocol_error("The Codex SSE event exceeded the safe size limit.")
  }

  lines <- strsplit(block, "\n", fixed = TRUE)[[1L]]
  data_lines <- character()
  event_name <- NULL

  for (line in lines) {
    # SSE comments are heartbeats and must not be interpreted as events.
    if (!nzchar(line) || startsWith(line, ":")) next

    colon <- regexpr(":", line, fixed = TRUE)[[1L]]
    if (colon < 0L) {
      field <- line
      field_value <- ""
    } else {
      field <- substr(line, 1L, colon - 1L)
      field_value <- substr(line, colon + 1L, nchar(line))
      # The SSE grammar removes at most one leading space after the colon.
      if (startsWith(field_value, " ")) {
        field_value <- substr(field_value, 2L, nchar(field_value))
      }
    }

    if (identical(field, "data")) {
      data_lines <- c(data_lines, field_value)
    } else if (identical(field, "event")) {
      event_name <- field_value
    }
  }

  if (length(data_lines) == 0L) {
    return(NULL)
  }
  data <- paste0(data_lines, collapse = "\n")
  if (identical(data, "[DONE]")) {
    return("__codex_sse_done__")
  }
  if (!nzchar(data)) {
    codex_sse_protocol_error("The Codex SSE stream contained an empty event payload.")
  }

  value <- tryCatch(
    jsonlite::fromJSON(data, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (!is.list(value)) {
    codex_sse_protocol_error("The Codex SSE stream contained invalid JSON.")
  }

  # A few SSE implementations put the event name in the field rather than in
  # the JSON envelope.  Preserve the payload's type when present, and use the
  # field only as a compatibility fallback.
  if (is.null(value$type) && is.character(event_name) && length(event_name) == 1L) {
    value$type <- event_name
  }
  value
}

codex_parse_sse <- function(value, max_event_bytes = 1024L * 1024L) {
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    codex_sse_protocol_error("The Codex SSE response was not text.")
  }
  if (!is.numeric(max_event_bytes) || length(max_event_bytes) != 1L ||
        !is.finite(max_event_bytes) || max_event_bytes < 1) {
    codex_sse_protocol_error("The Codex SSE event size limit is invalid.")
  }
  max_event_bytes <- as.numeric(max_event_bytes)

  # Normalize CRLF and lone CR, then parse blocks ourselves so a final event
  # without a trailing blank line is still handled according to SSE framing.
  # R's PCRE2 build does not accept a `\\u` escape in a regular expression;
  # remove a UTF-8 BOM with ordinary string operations instead.
  if (startsWith(value, "\ufeff")) value <- substring(value, 2L)
  value <- gsub("\r\n?", "\n", value, perl = TRUE)
  lines <- strsplit(value, "\n", fixed = TRUE)[[1L]]

  blocks <- list()
  current <- character()
  for (line in lines) {
    if (identical(line, "")) {
      if (length(current) > 0L) {
        blocks[[length(blocks) + 1L]] <- paste0(current, collapse = "\n")
        current <- character()
      }
    } else {
      current <- c(current, line)
    }
  }
  if (length(current) > 0L) {
    blocks[[length(blocks) + 1L]] <- paste0(current, collapse = "\n")
  }

  events <- list()
  done_seen <- FALSE
  for (block in blocks) {
    parsed <- codex_sse_parse_block(block, max_event_bytes = max_event_bytes)
    if (identical(parsed, "__codex_sse_done__")) {
      done_seen <- TRUE
    } else if (is.list(parsed)) {
      events[[length(events) + 1L]] <- parsed
    }
  }

  attr(events, "done_seen") <- done_seen
  class(events) <- c("codex_sse_events", "list")
  events
}

codex_sse_error <- function(event, message = "The Codex stream returned an error.") {
  error <- if (is.list(event)) event$error else NULL
  if (!is.list(error) && is.list(event$response)) error <- event$response$error

  detail <- NULL
  if (is.list(error)) {
    detail <- error$message
    if (is.null(detail)) detail <- error$code
    if (is.null(detail)) detail <- error$type
  } else if (is.character(error) && length(error) == 1L) {
    detail <- error
  }
  detail <- codex_sanitize_error_detail(detail)
  if (!is.null(detail) && nzchar(detail)) message <- paste(message, detail)
  rlang::abort(message, class = "codex_generation_error")
}

codex_extract_response_text <- function(value) {
  if (!is.list(value) || !is.list(value$output)) {
    return(character())
  }

  pieces <- character()
  for (item in value$output) {
    if (!is.list(item)) next
    if (identical(item$type, "message") && is.list(item$content)) {
      for (content in item$content) {
        is_text <- is.list(content) && identical(content$type, "output_text") &&
          is.character(content$text) && length(content$text) == 1L
        if (is_text) {
          pieces <- c(pieces, content$text)
        }
      }
    } else {
      is_text <- identical(item$type, "output_text") &&
        is.character(item$text) && length(item$text) == 1L
      if (!is_text) next
      pieces <- c(pieces, item$text)
    }
  }
  pieces
}

codex_parse_sse_response <- function(events) {
  if (!is.list(events)) {
    codex_sse_protocol_error("The Codex SSE event sequence was malformed.")
  }

  pieces <- character()
  done_text <- character()
  terminal <- NULL
  terminal_type <- NULL

  for (event in events) {
    if (!is.list(event)) {
      codex_sse_protocol_error("The Codex SSE event sequence was malformed.")
    }
    type <- codex_sse_event_type(event)
    if (is.null(type)) next

    if (identical(type, "response.output_text.delta")) {
      if (is.character(event$delta) && length(event$delta) == 1L) {
        pieces <- c(pieces, event$delta)
      }
    } else if (identical(type, "response.output_text.done")) {
      if (is.character(event$text) && length(event$text) == 1L) {
        done_text <- c(done_text, event$text)
      }
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
    }
    # Unknown event names are intentionally ignored.  Codex can add progress,
    # tool, or metadata events without breaking a text-only client.
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

  if (length(pieces) > 0L) {
    assembled <- paste0(pieces, collapse = "")
    if (nzchar(assembled)) {
      return(assembled)
    }
  }
  if (length(done_text) > 0L) {
    assembled <- paste0(done_text, collapse = "")
    if (nzchar(assembled)) {
      return(assembled)
    }
  }

  terminal_text <- codex_extract_response_text(terminal)
  if (length(terminal_text) > 0L) {
    assembled <- paste0(terminal_text, collapse = "")
    if (nzchar(assembled)) {
      return(assembled)
    }
  }

  codex_sse_protocol_error(
    "The terminal Codex SSE event contained no response output text."
  )
}

codex_is_sse_body <- function(content_type, body) {
  declared_sse <- is.character(content_type) && length(content_type) == 1L &&
    !is.na(content_type) && grepl("^text/event-stream(?:[;[:space:]]|$)",
    tolower(trimws(content_type)),
    perl = TRUE
  )
  has_bom <- is.character(body) && length(body) == 1L && !is.na(body) &&
    startsWith(body, "\ufeff")
  body_for_sniff <- if (has_bom) {
    substring(body, 2L)
  } else {
    body
  }
  sniffed_sse <- is.character(body_for_sniff) && length(body_for_sniff) == 1L &&
    !is.na(body_for_sniff) &&
    grepl("^[[:space:]]*(?:event:|data:|:)", body_for_sniff, perl = TRUE)
  isTRUE(declared_sse || sniffed_sse)
}

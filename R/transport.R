# HTTP request construction and response fallback parsing.

codex_request_body <- function(
  prompt,
  model = codex_default_model(),
  instructions = "You are a helpful assistant. Follow the user's output instructions exactly.",
  effort = NULL
) {
  if (!is.character(prompt) || length(prompt) != 1L || is.na(prompt) || !nzchar(prompt)) {
    rlang::abort(
      "`prompt` must be one non-empty string.",
      class = "codex_request_error"
    )
  }
  if (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model)) {
    rlang::abort(
      "`model` must be one non-empty string.",
      class = "codex_request_error"
    )
  }
  if (!is.character(instructions) || length(instructions) != 1L ||
        is.na(instructions) || !nzchar(instructions)) {
    rlang::abort(
      "`instructions` must be one non-empty string.",
      class = "codex_request_error"
    )
  }

  if (!is.null(effort) &&
      (!is.character(effort) || length(effort) != 1L || is.na(effort) ||
       !nzchar(effort))) {
    rlang::abort(
      "`effort` must be NULL or one non-empty string.",
      class = "codex_request_error"
    )
  }

  body <- list(
    model = model,
    instructions = instructions,
    input = list(list(
      role = "user",
      content = list(list(type = "input_text", text = prompt))
    )),
    # Do not retain server-side state for this narrow transport.
    store = FALSE,
    # Subscription-backed Responses currently requires streaming, even though
    # this package buffers the fixture/live body before assembling text.
    stream = TRUE
  )
  if (!is.null(effort)) {
    # Match ellmer's OpenAI Responses mapping exactly. The catalog owns the
    # allowed effort vocabulary; this transport forwards it unchanged.
    body$reasoning <- list(effort = effort, summary = "auto")
  }
  body
}

codex_error_detail_value <- function(value) {
  if (!is.list(value)) {
    return(NULL)
  }

  detail <- value$detail
  error <- value$error
  if (is.list(error)) {
    detail <- error$message
    if (is.null(detail)) detail <- error$code
    if (is.null(detail)) detail <- error$type
  } else if (is.character(error) && length(error) == 1L && !is.na(error)) {
    detail <- error
  }
  codex_sanitize_error_detail(detail)
}

codex_error_detail <- function(response) {
  value <- tryCatch(
    httr2::resp_body_json(response, simplifyVector = FALSE),
    error = function(error) NULL
  )
  codex_error_detail_value(value)
}

codex_abort_response <- function(response) {
  status <- tryCatch(httr2::resp_status(response), error = function(error) NA_integer_)
  detail <- codex_error_detail(response)
  suffix <- if (is.null(detail) || !nzchar(detail)) "" else paste0(" ", detail)

  if (status %in% c(401L, 403L, 402L)) {
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
  } else if (status >= 500L && status <= 599L) {
    message <- paste0("The Codex service failed while handling the request.", suffix)
    class <- "codex_server_error"
  } else if (is.na(status)) {
    message <- "The Codex transport returned an invalid HTTP response."
    class <- "codex_protocol_error"
  } else {
    message <- sprintf("The Codex transport returned HTTP %d.%s", status, suffix)
    class <- "codex_protocol_error"
  }
  rlang::abort(message, class = class)
}

codex_request <- function(
  prompt,
  auth,
  model = codex_default_model(),
  endpoint = codex_responses_url(),
  effort = NULL
) {
  if (!is.character(endpoint) || length(endpoint) != 1L || is.na(endpoint) ||
        !grepl("^https://", endpoint, perl = TRUE)) {
    rlang::abort(
      "The Codex transport endpoint must be an HTTPS URL.",
      class = "codex_request_error"
    )
  }

  headers <- codex_request_headers(auth)
  request <- httr2::request(endpoint) |>
    httr2::req_headers(!!!headers) |>
    httr2::req_body_json(
      codex_request_body(prompt, model, effort = effort),
      auto_unbox = TRUE
    ) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(response) FALSE)

  response <- tryCatch(
    httr2::req_perform(request),
    error = function(error) {
      rlang::abort(
        "The Codex request failed because of an ordinary network error.",
        class = "codex_network_error"
      )
    }
  )
  status <- tryCatch(httr2::resp_status(response), error = function(error) NA_integer_)
  if (is.na(status) || status < 200L || status >= 300L) {
    codex_abort_response(response)
  }
  response
}

codex_parse_response <- function(value) {
  if (!is.list(value)) {
    rlang::abort(
      "The Codex response did not match the expected Responses JSON shape.",
      class = "codex_protocol_changed_error"
    )
  }

  pieces <- codex_extract_response_text(value)
  if (length(pieces) == 0L && is.character(value$output_text) &&
        length(value$output_text) == 1L && !is.na(value$output_text) &&
        nzchar(value$output_text)) {
    pieces <- value$output_text
  }
  if (length(pieces) == 0L) {
    rlang::abort(
      "The Codex response contained no output text; the upstream protocol may have changed.",
      class = "codex_protocol_changed_error"
    )
  }
  paste0(pieces, collapse = "")
}

codex_generate <- function(
  prompt,
  model = codex_default_model(),
  auth = NULL,
  effort = NULL
) {
  explicit_auth <- !is.null(auth)
  if (is.null(auth)) {
    auth <- codex_auth()
  }

  # Refresh once when required.  There is intentionally no retry-on-401 or
  # generation retry: a request may already have been accepted upstream.
  if (exists("codex_token_expired", mode = "function") &&
        isTRUE(codex_token_expired(auth))) {
    auth <- codex_refresh(auth, persist = !explicit_auth)
  }

  response <- codex_request(
    prompt,
    auth = auth,
    model = model,
    effort = effort
  )
  content_type <- tryCatch(
    httr2::resp_content_type(response),
    error = function(error) NA_character_
  )
  body <- tryCatch(
    httr2::resp_body_string(response),
    error = function(error) NULL
  )
  if (!is.character(body) || length(body) != 1L || is.na(body)) {
    rlang::abort(
      "The Codex response body could not be read.",
      class = "codex_protocol_changed_error"
    )
  }

  if (codex_is_sse_body(content_type, body)) {
    return(codex_parse_sse_response(codex_parse_sse(body)))
  }

  value <- tryCatch(
    jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (!is.list(value)) {
    rlang::abort(
      "The Codex response was not valid JSON; the upstream protocol may require streaming or may have changed.",
      class = "codex_protocol_changed_error"
    )
  }
  codex_parse_response(value)
}

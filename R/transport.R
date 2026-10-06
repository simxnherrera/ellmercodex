# HTTP request construction and response fallback parsing.

codex_request_body <- function(
  prompt,
  model = NULL,
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

# Documented ChatGPT plan usage error codes and the package conditions they
# map to. The more specific class comes first; the second keeps the
# established transport parent stable for existing handlers.
codex_plan_error_info <- function(code) {
  if (!is.character(code) || length(code) != 1L || is.na(code)) {
    return(NULL)
  }
  switch(
    code,
    subscription_sharing_usage_limit_exceeded = list(
      class = c("codex_usage_limit_error", "codex_rate_limit_error"),
      message = paste(
        "The ChatGPT plan usage limit was reached. Pause requests and check",
        "usage in ChatGPT settings."
      )
    ),
    subscription_sharing_usage_unavailable = ,
    subscription_sharing_user_unavailable = list(
      class = c("codex_usage_unavailable_error", "codex_server_error"),
      message = paste(
        "ChatGPT plan usage is temporarily unavailable. Credentials were kept;",
        "retry later with backoff."
      )
    ),
    subscription_sharing_user_not_eligible = list(
      class = c("codex_plan_ineligible_error", "codex_authentication_error"),
      message = paste(
        "ChatGPT plan usage is unavailable for this user, workspace, or policy.",
        "Signing in again will not help."
      )
    ),
    subscription_sharing_invalid_user = list(
      class = "codex_authentication_error",
      message = "The ChatGPT subscriber could not be validated. Run codex_login() again."
    ),
    subscription_sharing_route_not_supported = ,
    chatpass_v2_scope_not_authorized = ,
    chatpass_v2_invalid_authorization_context = list(
      class = "codex_authentication_error",
      message = "The ChatGPT plan authorization does not permit this request."
    ),
    subscription_sharing_unsupported_capability = list(
      class = c("codex_unsupported_capability_error", "codex_malformed_request_error"),
      message = paste(
        "The request used an input, tool, or model that ChatGPT plan usage",
        "does not support. Remove it before retrying."
      )
    ),
    NULL
  )
}

codex_error_fields <- function(value) {
  error <- if (is.list(value)) value$error else NULL
  if (!is.list(error) && is.list(value) && is.list(value$response)) error <- value$response$error
  code <- if (is.list(error)) error$code else NULL
  param <- if (is.list(error)) error$param else NULL
  list(
    code = if (is.character(code) && length(code) == 1L && !is.na(code)) code else NULL,
    param = if (is.character(param) && length(param) == 1L && !is.na(param)) param else NULL
  )
}

# Signal a documented plan error when `value` carries one; otherwise return
# NULL so the caller can fall back to its generic mapping.
codex_abort_plan_error <- function(value, detail = NULL) {
  fields <- codex_error_fields(value)
  info <- codex_plan_error_info(fields$code)
  if (is.null(info)) {
    return(invisible(NULL))
  }
  message <- info$message
  if (!is.null(fields$param)) {
    message <- paste0(message, " Parameter: ", codex_sanitize_error_detail(fields$param), ".")
  }
  rlang::abort(
    paste0(message, " (", fields$code, ")"),
    class = info$class,
    code = fields$code,
    param = fields$param
  )
}

codex_abort_response <- function(response) {
  status <- tryCatch(httr2::resp_status(response), error = function(error) NA_integer_)
  value <- tryCatch(
    httr2::resp_body_json(response, simplifyVector = FALSE),
    error = function(error) NULL
  )
  codex_abort_plan_error(value)
  detail <- codex_error_detail_value(value)
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
  model = NULL,
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
  model = NULL,
  auth = NULL,
  effort = NULL
) {
  persist <- FALSE
  if (is.null(auth)) {
    auth <- codex_auth()
    persist <- isTRUE(codex_session_persists())
  }

  if (is.null(model)) {
    model <- codex_select_model(auth = auth, effort = effort)$model
  }

  # Refresh once when required.  There is intentionally no retry-on-401 or
  # generation retry: a request may already have been accepted upstream.
  if (exists("codex_token_expired", mode = "function") &&
        isTRUE(codex_token_expired(auth))) {
    auth <- codex_refresh(auth, persist = persist)
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

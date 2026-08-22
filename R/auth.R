# OAuth primitives and the public authentication lifecycle.

`%||%` <- function(x, y) if (is.null(x)) y else x

.codex_session <- new.env(parent = emptyenv())
.codex_session$auth <- NULL
.codex_session$persist <- FALSE

codex_session_set <- function(auth, persist = FALSE) {
  if (!inherits(auth, "codex_auth")) {
    codex_auth_abort("The Codex session credential was malformed.", "codex_auth_argument_error")
  }
  .codex_session$auth <- auth
  .codex_session$persist <- isTRUE(persist)
  invisible(auth)
}

codex_session_get <- function() {
  auth <- .codex_session$auth
  if (inherits(auth, "codex_auth")) auth else NULL
}

codex_session_persists <- function() {
  isTRUE(.codex_session$persist)
}

codex_session_clear <- function() {
  .codex_session$auth <- NULL
  .codex_session$persist <- FALSE
  invisible(TRUE)
}

codex_base64url_encode <- function(value) {
  if (is.character(value)) value <- charToRaw(value)
  if (!is.raw(value)) {
    codex_auth_abort("The value to encode must be raw or character data.", "codex_oauth_argument_error")
  }
  encoded <- openssl::base64_encode(value)
  encoded <- chartr("+/", "-_", encoded)
  sub("=+$", "", encoded)
}

codex_base64url_decode <- function(value) {
  codex_auth_require_string(value, "value")
  if (!grepl("^[A-Za-z0-9_-]+$", value)) {
    codex_auth_abort("The encoded OAuth value was malformed.", "codex_oauth_argument_error")
  }
  value <- chartr("-_", "+/", value)
  padding <- (4L - (nchar(value) %% 4L)) %% 4L
  if (padding > 0L) value <- paste0(value, strrep("=", padding))
  tryCatch(openssl::base64_decode(value), error = function(error) {
    codex_auth_abort("The encoded OAuth value was malformed.", "codex_oauth_argument_error")
  })
}

codex_pkce <- function() {
  # 64 random bytes encode to a verifier well within RFC 7636's bounds.
  verifier <- codex_base64url_encode(openssl::rand_bytes(64L))
  challenge <- codex_base64url_encode(openssl::sha256(charToRaw(verifier)))
  list(verifier = verifier, challenge = challenge)
}

codex_oauth_state <- function() {
  codex_base64url_encode(openssl::rand_bytes(32L))
}

codex_validate_state <- function(expected, received) {
  is.character(expected) && length(expected) == 1L && !is.na(expected) &&
    is.character(received) && length(received) == 1L && !is.na(received) &&
    nzchar(expected) && identical(expected, received)
}

codex_parse_query <- function(query) {
  if (is.null(query) || length(query) == 0L || is.na(query) || !nzchar(query)) {
    return(list())
  }
  query <- sub("^\\?", "", query)
  if (!nzchar(query)) {
    return(list())
  }

  decode <- function(value) {
    # URLdecode() intentionally does not apply application/x-www-form-urlencoded
    # '+' semantics, while QUERY_STRING values commonly use them.
    utils::URLdecode(gsub("+", " ", value, fixed = TRUE))
  }
  pairs <- strsplit(query, "&", fixed = TRUE)[[1L]]
  out <- lapply(pairs, function(pair) {
    parts <- strsplit(pair, "=", fixed = TRUE)[[1L]]
    name <- decode(parts[[1L]])
    value <- if (length(parts) > 1L) decode(paste(parts[-1L], collapse = "=")) else ""
    list(name = name, value = value)
  })
  names <- vapply(out, `[[`, "", "name")
  values <- lapply(out, `[[`, "value")
  # Invalid/empty names are not useful to the callback and should never become
  # surprising names in a condition or diagnostic.
  keep <- nzchar(names)
  stats::setNames(values[keep], names[keep])
}

codex_authorize_url <- function(pkce, state) {
  if (!is.list(pkce) || !codex_auth_scalar_character(pkce$challenge) ||
        !codex_auth_scalar_character(pkce$verifier)) {
    codex_auth_abort("The PKCE values were malformed.", "codex_oauth_argument_error")
  }
  codex_auth_require_string(state, "state")
  params <- list(
    response_type = "code",
    client_id = codex_oauth_client_id(),
    redirect_uri = codex_redirect_uri(),
    scope = "openid profile email offline_access",
    code_challenge = pkce$challenge,
    code_challenge_method = "S256",
    id_token_add_organizations = "true",
    codex_cli_simplified_flow = "true",
    state = state,
    originator = codex_originator()
  )
  httr2::url_modify(codex_authorization_url(), query = params)
}

codex_callback_html <- function(success) {
  status <- if (isTRUE(success)) "Authorization received" else "Authorization failed"
  paste0(
    "<!doctype html><html><head><meta charset='utf-8'><title>", status,
    "</title></head><body><h1>", status,
    "</h1><p>You may close this window and return to R.</p></body></html>"
  )
}

codex_callback_result <- function(query, expected_state) {
  query <- if (is.list(query)) query else list()
  if (!codex_validate_state(expected_state, query$state)) {
    return(list(code = NULL, error = "OAuth state validation failed."))
  }

  code <- query$code
  if (codex_auth_scalar_character(code)) {
    return(list(code = code, error = NULL))
  }

  error_code <- query$error
  safe_error <- codex_auth_scalar_character(error_code) &&
    grepl("^[A-Za-z0-9._-]{1,80}$", error_code)
  if (safe_error) {
    return(list(code = NULL, error = sprintf("Authorization failed (%s).", error_code)))
  }

  parameter_names <- setdiff(names(query), c("code", "state"))
  parameter_names <- parameter_names[
    grepl("^[A-Za-z0-9._-]{1,80}$", parameter_names)
  ]
  suffix <- if (length(parameter_names) == 0L) {
    ""
  } else {
    sprintf(" Safe parameter names received: %s.", paste(parameter_names, collapse = ", "))
  }
  list(
    code = NULL,
    error = paste0("The OAuth callback did not contain an authorization code.", suffix)
  )
}

codex_wait_for_callback <- function(expected_state, timeout = 300, on_ready = NULL) {
  codex_auth_require_string(expected_state, "expected_state")
  if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) {
    codex_auth_abort("`timeout` must be one positive number of seconds.", "codex_auth_argument_error")
  }

  result <- new.env(parent = emptyenv())
  result$done <- FALSE
  result$code <- NULL
  result$error <- NULL

  app <- list(call = function(request) {
    path <- request$PATH_INFO %||% request$REQUEST_URI %||% ""
    path <- sub("\\?.*$", "", path)
    if (!identical(path, "/auth/callback")) {
      return(list(
        status = 404L,
        headers = list("Content-Type" = "text/plain; charset=utf-8"),
        body = "Not found"
      ))
    }

    query <- codex_parse_query(request$QUERY_STRING %||% "")
    callback <- codex_callback_result(query, expected_state)
    result$error <- callback$error
    result$code <- callback$code
    result$done <- TRUE

    ok <- is.null(result$error)
    list(
      status = if (ok) 200L else 400L,
      headers = list("Content-Type" = "text/html; charset=utf-8"),
      body = codex_callback_html(ok)
    )
  })

  server <- tryCatch(
    httpuv::startServer("127.0.0.1", codex_callback_port(), app),
    error = function(error) {
      codex_auth_abort(
        sprintf(
          paste0(
            "Could not bind the required OAuth callback at 127.0.0.1:%d. ",
            "Close any process using that port and try again."
          ),
          codex_callback_port()
        ),
        "codex_oauth_callback_error"
      )
    }
  )
  on.exit(try(httpuv::stopServer(server), silent = TRUE), add = TRUE)

  # The listener must exist before opening the authorization URL.
  if (is.function(on_ready)) {
    tryCatch(on_ready(), error = function(error) {
      codex_auth_abort(
        "Could not open a browser for Codex authentication.",
        "codex_oauth_browser_error"
      )
    })
  }

  started <- Sys.time()
  while (!isTRUE(result$done)) {
    httpuv::service(timeoutMs = 100L)
    elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    if (elapsed >= timeout) {
      codex_auth_abort("Timed out waiting for the OAuth browser callback.", "codex_oauth_timeout")
    }
  }

  if (!is.null(result$error)) {
    codex_auth_abort(result$error, "codex_oauth_callback_error")
  }
  result$code
}

codex_token_response <- function(response, operation = "token exchange") {
  status <- tryCatch(httr2::resp_status(response), error = function(error) NA_integer_)
  if (!is.finite(status) || status < 200L || status >= 300L) {
    code <- if (identical(operation, "refresh")) "codex_refresh_error" else "codex_token_exchange_error"
    codex_auth_abort(
      sprintf(
        "Codex OAuth %s failed (HTTP %s). Please authenticate again.",
        operation,
        if (is.finite(status)) status else "unknown"
      ),
      code
    )
  }

  value <- tryCatch(
    httr2::resp_body_json(response, simplifyVector = TRUE),
    error = function(error) NULL
  )
  valid_access_token <- is.list(value) && codex_auth_scalar_character(value$access_token)
  if (!valid_access_token) {
    code <- if (identical(operation, "refresh")) "codex_refresh_error" else "codex_token_exchange_error"
    codex_auth_abort(
      sprintf("Codex OAuth %s returned a malformed credential response.", operation),
      code
    )
  }
  value
}

codex_jwt_claims <- function(token) {
  if (!codex_auth_scalar_character(token)) {
    return(NULL)
  }
  parts <- strsplit(token, ".", fixed = TRUE)[[1L]]
  if (length(parts) != 3L || !nzchar(parts[[2L]])) {
    return(NULL)
  }
  tryCatch(
    jsonlite::fromJSON(
      rawToChar(codex_base64url_decode(parts[[2L]])),
      simplifyVector = TRUE
    ),
    error = function(error) NULL
  )
}

codex_account_id <- function(access_token, id_token = NULL) {
  candidates <- Filter(Negate(is.null), list(id_token, access_token))
  for (token in candidates) {
    claims <- codex_jwt_claims(token)
    if (!is.list(claims)) next
    namespaced <- claims[["https://api.openai.com/auth"]]
    if (is.character(namespaced) && length(namespaced) == 1L) {
      namespaced <- tryCatch(jsonlite::fromJSON(namespaced, simplifyVector = TRUE), error = function(error) NULL)
    }
    account_id <- if (is.list(namespaced)) namespaced$chatgpt_account_id else NULL
    account_id <- account_id %||% claims$chatgpt_account_id
    if (codex_auth_scalar_character(account_id)) {
      return(account_id)
    }
  }
  codex_auth_abort(
    "The OAuth credential did not contain the account identifier required by the Codex transport.",
    "codex_account_error"
  )
}

codex_auth_from_tokens <- function(tokens, previous = NULL) {
  if (!is.list(tokens) || !codex_auth_scalar_character(tokens$access_token)) {
    codex_auth_abort(
      "The OAuth token response did not contain an access token.",
      "codex_token_exchange_error"
    )
  }
  refresh_token <- tokens$refresh_token %||% previous$refresh_token
  id_token <- tokens$id_token %||% previous$id_token
  if (!codex_auth_scalar_character(refresh_token)) {
    codex_auth_abort(
      "The OAuth credential response did not contain a refresh token.",
      "codex_token_exchange_error"
    )
  }

  expires_in <- suppressWarnings(as.numeric(tokens$expires_in %||% NA_real_))
  if (length(expires_in) != 1L || !is.finite(expires_in) || expires_in < 0) expires_in <- NA_real_
  expires_at <- if (is.finite(expires_in)) as.numeric(Sys.time()) + expires_in else NA_real_
  account_id <- codex_account_id(tokens$access_token, id_token)

  structure(
    list(
      access_token = tokens$access_token,
      refresh_token = refresh_token,
      id_token = id_token,
      account_id = account_id,
      expires_at = expires_at
    ),
    class = c("codex_auth", "list")
  )
}

codex_token_expires_at <- function(auth) {
  if (!is.list(auth)) {
    return(NA_real_)
  }
  claims <- codex_jwt_claims(auth$access_token)
  jwt_exp <- if (is.list(claims)) suppressWarnings(as.numeric(claims$exp %||% NA_real_)) else NA_real_
  if (length(jwt_exp) == 1L && is.finite(jwt_exp)) {
    jwt_exp
  } else {
    value <- suppressWarnings(as.numeric(auth$expires_at %||% NA_real_))
    if (length(value) == 1L && is.finite(value)) value else NA_real_
  }
}

codex_token_expired <- function(auth, skew = 60, now = as.numeric(Sys.time())) {
  expires_at <- codex_token_expires_at(auth)
  !is.finite(expires_at) || expires_at <= (now + skew)
}

codex_exchange_code <- function(code, verifier) {
  codex_auth_require_string(code, "code")
  codex_auth_require_string(verifier, "verifier")
  request <- httr2::request(codex_token_url()) |>
    httr2::req_body_form(
      grant_type = "authorization_code",
      code = code,
      redirect_uri = codex_redirect_uri(),
      client_id = codex_oauth_client_id(),
      code_verifier = verifier
    ) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) {
    codex_auth_abort(
      "Codex OAuth token exchange failed because of a network error.",
      "codex_token_exchange_error"
    )
  })
  codex_token_response(response, "token exchange")
}

codex_refresh <- function(auth, persist = TRUE) {
  if (!inherits(auth, "codex_auth") || !codex_auth_scalar_character(auth$refresh_token)) {
    codex_auth_abort("The Codex credential cannot be refreshed.", "codex_refresh_error")
  }
  request <- httr2::request(codex_token_url()) |>
    httr2::req_body_form(
      grant_type = "refresh_token",
      refresh_token = auth$refresh_token,
      client_id = codex_oauth_client_id()
    ) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) {
    codex_auth_abort(
      "Codex credential refresh failed because of a network error; run codex_login() if it persists.",
      "codex_refresh_error"
    )
  })
  tokens <- codex_token_response(response, "refresh")
  refreshed <- tryCatch(codex_auth_from_tokens(tokens, previous = auth), error = function(error) {
    if (inherits(error, "codex_refresh_error")) stop(error)
    codex_auth_abort(codex_redact(conditionMessage(error)), "codex_refresh_error")
  })
  # Persist the replacement before returning it: refresh tokens are commonly
  # rotated, and losing the new value would invalidate the next request.
  if (isTRUE(persist)) codex_credentials_store(refreshed)
  refreshed
}

codex_auth <- function(force_refresh = FALSE) {
  auth <- codex_session_get()
  persist <- codex_session_persists()
  if (is.null(auth)) {
    auth <- codex_credentials_load()
    persist <- TRUE
    codex_session_set(auth, persist = TRUE)
  }
  if (isTRUE(force_refresh) || codex_token_expired(auth)) {
    auth <- codex_refresh(auth, persist = persist)
    codex_session_set(auth, persist = persist)
  }
  auth
}

codex_open_browser <- function(url) {
  codex_auth_require_string(url, "url")
  tryCatch(
    utils::browseURL(url, verbose = FALSE),
    error = function(error) {
      codex_auth_abort(
        "Could not open a browser for Codex authentication.",
        "codex_oauth_browser_error"
      )
    }
  )
  invisible(TRUE)
}

#' Sign in to a Codex subscription with browser OAuth.
#'
#' `codex_login()` is the explicit authentication entry point. It opens a
#' browser only when called by the user, validates a loopback callback with
#' PKCE and OAuth state, and stores the resulting credential in the OS
#' credential store by default. If the file backend is explicitly enabled,
#' the credential is instead stored in the encrypted file described in the
#' package overview. It never reads credentials created by Codex CLI or
#' another application.
#'
#' @param persist Whether to save the credential for later sessions. The
#'   default is `TRUE`; use `FALSE` for a process-only session.
#' @param timeout Maximum callback wait in seconds. This must be one positive
#'   number. The loopback listener is closed when authentication succeeds,
#'   fails, or times out. When `persist = FALSE`, the credential remains
#'   available to [chat_codex()] only in the current R process.
#'
#' @return An internal `codex_auth` object. Use [codex_account()] for a safe
#'   account summary; token fields are intentionally not printed.
#' @note This function is interactive: it opens the default browser and
#'   listens on the local loopback callback at port 1455. It does not revoke
#'   a remote session; use [codex_logout()] to remove the local credential
#'   owned by this package.
#' @section Conditions:
#' Invalid arguments signal `codex_auth_argument_error`; callback, browser, and
#' token failures use `codex_oauth_callback_error`, `codex_oauth_browser_error`,
#' or `codex_token_exchange_error` as appropriate.
#' @examplesIf interactive()
#' auth <- codex_login()
#' codex_account(auth)
#' @export
codex_login <- function(persist = TRUE, timeout = 300) {
  if (!is.logical(persist) || length(persist) != 1L || is.na(persist)) {
    codex_auth_abort("`persist` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) {
    codex_auth_abort("`timeout` must be one positive number of seconds.", "codex_auth_argument_error")
  }

  pkce <- codex_pkce()
  state <- codex_oauth_state()
  authorization_url <- codex_authorize_url(pkce, state)
  code <- codex_wait_for_callback(
    state,
    timeout = timeout,
    on_ready = function() codex_open_browser(authorization_url)
  )
  tokens <- codex_exchange_code(code, pkce$verifier)
  auth <- codex_auth_from_tokens(tokens)
  if (isTRUE(persist)) codex_credentials_store(auth)
  codex_session_set(auth, persist = persist)
  auth
}

#' Show a redacted Codex authentication summary.
#'
#' The account identifier and all token material are deliberately replaced or
#' omitted. Calling this function does not refresh a credential or contact the
#' network.
#'
#' @param auth Optional in-memory credential. If omitted, the current
#'   process-local session and then the package's own credential store are
#'   checked.
#' @return A one-row data frame with columns:
#'     \item{`authenticated`}{Logical; whether a valid package credential was found.}
#'     \item{`account`}{Always `"<redacted>"`; account identifiers are never returned.}
#'     \item{`expires_at`}{The access-token expiry as a UTC `POSIXct` value, or `NA` when unauthenticated.}
#' @section Conditions:
#' A malformed in-memory credential signals `codex_auth_argument_error` and a
#' malformed stored value signals `codex_credential_store_error`.
#' @examplesIf interactive()
#' codex_account()
#' @export
codex_account <- function(auth = NULL) {
  if (is.null(auth)) auth <- codex_session_get()
  if (is.null(auth)) auth <- codex_credentials_load(required = FALSE)
  if (is.null(auth)) {
    return(data.frame(
      authenticated = FALSE,
      account = "<redacted>",
      expires_at = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"),
      stringsAsFactors = FALSE
    ))
  }
  if (!inherits(auth, "codex_auth")) {
    codex_auth_abort("`auth` must be a Codex credential.", "codex_auth_argument_error")
  }
  expiry <- codex_token_expires_at(auth)
  data.frame(
    authenticated = TRUE,
    account = "<redacted>",
    expires_at = as.POSIXct(expiry, origin = "1970-01-01", tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

#' @export
print.codex_auth <- function(x, ...) {
  print(codex_account(x), ...)
  invisible(x)
}

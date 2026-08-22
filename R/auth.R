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

  expires_at <- suppressWarnings(as.numeric(tokens$expires_at %||% NA_real_))
  if (length(expires_at) != 1L || !is.finite(expires_at) || expires_at < 0) {
    expires_in <- suppressWarnings(as.numeric(tokens$expires_in %||% NA_real_))
    if (length(expires_in) != 1L || !is.finite(expires_in) || expires_in < 0) {
      expires_in <- NA_real_
    }
    expires_at <- if (is.finite(expires_in)) as.numeric(Sys.time()) + expires_in else NA_real_
  }
  account_id <- tryCatch(
    codex_account_id(tokens$access_token, id_token),
    error = function(error) {
      previous_account <- if (is.list(previous)) previous$account_id else NULL
      if (codex_auth_scalar_character(previous_account)) previous_account else stop(error)
    }
  )

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

codex_refresh <- function(auth, persist = TRUE) {
  if (!inherits(auth, "codex_auth") || !codex_auth_scalar_character(auth$refresh_token)) {
    codex_auth_abort("The Codex credential cannot be refreshed.", "codex_refresh_error")
  }
  if (isTRUE(persist)) {
    # httr2 owns the persisted token and refresh-token rotation. This path is
    # used only for package-managed credentials; injected credentials remain
    # process-local and use the explicit exchange below.
    tokens <- codex_oauth_token_cached(
      cache_disk = TRUE,
      reauth = FALSE,
      allow_interactive = FALSE
    )
    return(codex_auth_from_tokens(tokens, previous = auth))
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

#' Sign in to a Codex subscription with browser OAuth.
#'
#' `codex_login()` is the explicit authentication entry point. It opens a
#' browser only when called by the user, uses httr2's PKCE-protected OAuth code
#' flow, and stores the resulting credential in httr2's encrypted user-level
#' cache by default. It does not use the OS keyring. The package never reads
#' credentials created by Codex CLI or another application.
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
#' Invalid arguments signal `codex_auth_argument_error`; callback and token
#' failures use `codex_oauth_callback_error` or `codex_token_exchange_error` as
#' appropriate.
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

  tokens <- codex_oauth_token_cached(
    cache_disk = isTRUE(persist),
    reauth = TRUE,
    allow_interactive = TRUE,
    timeout = timeout
  )
  auth <- codex_auth_from_tokens(tokens)
  codex_session_set(auth, persist = persist)
  auth
}

#' Show a redacted Codex authentication summary.
#'
#' The account identifier and all token material are deliberately replaced or
#' omitted. Calling this function does not open a browser; an expired cached
#' credential may be refreshed by httr2.
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

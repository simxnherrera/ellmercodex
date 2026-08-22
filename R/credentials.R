# OAuth token caching and credential redaction.

# httr2 owns the on-disk cache. It encrypts cached tokens, scopes them to the
# named OAuth client, and refreshes them when they expire. The package never
# uses an OS keyring or reads another client's credential files.
codex_oauth_client <- function() {
  httr2::oauth_client(
    id = codex_oauth_client_id(),
    token_url = codex_token_url(),
    auth = "body",
    name = "ellmercodex"
  )
}

codex_oauth_scope <- function() {
  "openid profile email offline_access"
}

codex_oauth_flow <- function(
  client,
  allow_interactive = TRUE,
  auth_url = codex_authorization_url(),
  scope = codex_oauth_scope(),
  pkce = TRUE,
  auth_params = list(
    id_token_add_organizations = "true",
    codex_cli_simplified_flow = "true",
    originator = codex_originator()
  ),
  token_params = list(),
  redirect_uri = codex_redirect_uri(),
  timeout = 300
) {
  if (!isTRUE(allow_interactive)) {
    codex_auth_abort(
      "No stored ellmercodex credentials were found; run codex_login().",
      "codex_auth_missing"
    )
  }
  if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) {
    codex_auth_abort("`timeout` must be one positive number of seconds.", "codex_auth_argument_error")
  }
  # httr2 owns the browser and callback loop but does not expose a timeout
  # argument. A transient R time limit preserves codex_login()'s public timeout
  # contract without changing httr2's cache or OAuth implementation.
  setTimeLimit(elapsed = timeout, transient = TRUE)
  tryCatch(
    httr2::oauth_flow_auth_code(
      client = client,
      auth_url = auth_url,
      scope = scope,
      pkce = pkce,
      auth_params = auth_params,
      token_params = token_params,
      redirect_uri = redirect_uri
    ),
    error = function(error) {
      if (inherits(error, "codex_auth_error")) {
        stop(error)
      }
      if (grepl("time limit", conditionMessage(error), ignore.case = TRUE)) {
        codex_auth_abort("Timed out waiting for the OAuth browser callback.", "codex_oauth_timeout")
      }
      message <- codex_redact(conditionMessage(error))
      if (!codex_auth_scalar_character(message)) {
        message <- "The browser authentication flow did not complete."
      }
      codex_auth_abort(
        paste0("Codex browser authentication failed: ", message),
        "codex_oauth_callback_error"
      )
    }
  )
}

codex_oauth_token_cached <- function(
  cache_disk = TRUE,
  cache_key = NULL,
  reauth = FALSE,
  allow_interactive = reauth,
  timeout = 300
) {
  if (!is.logical(cache_disk) || length(cache_disk) != 1L || is.na(cache_disk)) {
    codex_auth_abort("`cache_disk` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  if (!is.logical(reauth) || length(reauth) != 1L || is.na(reauth)) {
    codex_auth_abort("`reauth` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  if (!is.logical(allow_interactive) || length(allow_interactive) != 1L || is.na(allow_interactive)) {
    codex_auth_abort(
      "`allow_interactive` must be one `TRUE` or `FALSE` value.",
      "codex_auth_argument_error"
    )
  }
  if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) {
    codex_auth_abort("`timeout` must be one positive number of seconds.", "codex_auth_argument_error")
  }

  client <- codex_oauth_client()
  flow_params <- list(
    allow_interactive = allow_interactive,
    auth_url = codex_authorization_url(),
    scope = codex_oauth_scope(),
    pkce = TRUE,
    auth_params = list(
      id_token_add_organizations = "true",
      codex_cli_simplified_flow = "true",
      originator = codex_originator()
    ),
    token_params = list(),
    redirect_uri = codex_redirect_uri(),
    timeout = timeout
  )
  tryCatch(
    httr2::oauth_token_cached(
      client = client,
      flow = codex_oauth_flow,
      flow_params = flow_params,
      cache_disk = cache_disk,
      cache_key = cache_key,
      reauth = reauth
    ),
    error = function(error) {
      if (inherits(error, "codex_auth_error")) {
        stop(error)
      }
      message <- codex_redact(conditionMessage(error))
      if (!codex_auth_scalar_character(message)) {
        message <- "The OAuth token flow did not complete."
      }
      codex_auth_abort(
        paste0("Codex OAuth token flow failed: ", message),
        if (isTRUE(reauth)) "codex_oauth_callback_error" else "codex_refresh_error"
      )
    }
  )
}

codex_redact <- function(x) {
  if (is.null(x)) {
    return(x)
  }
  if (length(x) == 0L) {
    return(x)
  }
  if (!is.character(x)) x <- as.character(x)

  redact_one <- function(value) {
    if (is.na(value)) {
      return(value)
    }
    value <- gsub(
      "Bearer[[:space:]]+[^[:space:],;]+",
      "Bearer <redacted>", value,
      ignore.case = TRUE, perl = TRUE
    )
    value <- gsub(
      "([?&](?:code|state|code_verifier|refresh_token|access_token|id_token)=)[^&#[:space:]]+",
      "\\1<redacted>", value,
      ignore.case = TRUE, perl = TRUE
    )
    value <- gsub(
      paste0(
        "((?:access_token|refresh_token|id_token|account_id|",
        "chatgpt[-_]account[-_]id)[[:space:]]*[:=][[:space:]]*)",
        "[^,};[:space:]]+"
      ),
      "\\1<redacted>", value,
      ignore.case = TRUE, perl = TRUE
    )
    value <- gsub(
      "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
      "<redacted-jwt>", value,
      perl = TRUE
    )
    value <- gsub(
      "(authorization[[:space:]]*:[[:space:]]*)[^,;[:space:]]+",
      "\\1<redacted>", value,
      ignore.case = TRUE, perl = TRUE
    )
    value
  }
  vapply(x, redact_one, character(1))
}

codex_credentials_valid <- function(value) {
  required_fields <- c("access_token", "refresh_token", "account_id", "expires_at")
  valid_string <- function(x) codex_auth_scalar_character(x)
  expiry <- if (is.list(value)) value$expires_at else NULL
  expiry_valid <- is.null(expiry) ||
    (is.numeric(expiry) && length(expiry) == 1L && (is.finite(expiry) || is.na(expiry)))
  is.list(value) && all(required_fields %in% names(value)) &&
    all(vapply(value[c("access_token", "refresh_token", "account_id")], valid_string, logical(1))) &&
    expiry_valid
}

codex_credentials_as_auth <- function(value) {
  if (!codex_credentials_valid(value)) {
    codex_auth_abort(
      "Stored ellmercodex credentials are malformed; run codex_logout() and codex_login().",
      "codex_credential_store_error"
    )
  }
  if (is.null(value$expires_at)) value$expires_at <- NA_real_
  structure(value, class = c("codex_auth", "list"))
}

codex_credentials_load <- function(required = TRUE) {
  if (!is.logical(required) || length(required) != 1L || is.na(required)) {
    codex_auth_abort("`required` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  token <- tryCatch(
    codex_oauth_token_cached(
      cache_disk = TRUE,
      reauth = FALSE,
      allow_interactive = FALSE
    ),
    error = function(error) {
      if (!isTRUE(required) && inherits(error, "codex_auth_missing")) {
        return(NULL)
      }
      stop(error)
    }
  )
  if (is.null(token)) {
    return(NULL)
  }
  auth <- tryCatch(
    codex_auth_from_tokens(token),
    error = function(error) {
      if (inherits(error, "codex_auth_error")) {
        stop(error)
      }
      codex_auth_abort(
        "Stored ellmercodex credentials are malformed; run codex_logout() and codex_login().",
        "codex_credential_store_error"
      )
    }
  )
  codex_credentials_as_auth(unclass(auth))
}

#' Remove only ellmercodex's stored Codex credential.
#'
#' This function clears only the package-named httr2 token cache and the
#' process-local session. It never removes Codex CLI credentials or another
#' application's entries.
#'
#' @return `TRUE`, invisibly. The process-local credential is cleared even if
#'   no persistent backend is available.
#' @note Logout removes local credential material but does not contact the
#'   remote service or revoke a remote session.
#' @section Conditions:
#' Logout is best effort and signals no backend details. Storage failures are
#' reported as `codex_credential_store_error` by the explicit login/refresh
#' paths that write credentials.
#' @examplesIf interactive()
#' codex_logout()
#' @export
codex_logout <- function() {
  codex_session_clear()
  client <- codex_oauth_client()
  try(httr2::oauth_cache_clear(client, cache_disk = TRUE), silent = TRUE)
  try(httr2::oauth_cache_clear(client, cache_disk = FALSE), silent = TRUE)
  invisible(TRUE)
}

# Offline-safe package and authentication diagnostics.

codex_diagnostic_dependencies <- function() {
  packages <- c("ellmer", "httr2", "httpuv", "jsonlite", "keyring", "openssl", "rlang", "coro")
  stats::setNames(vapply(packages, requireNamespace, logical(1), quietly = TRUE), packages)
}

codex_diagnostic_configuration <- function() {
  fn_env <- environment(codex_diagnostic_configuration)
  required <- c(
    "codex_oauth_client_id", "codex_authorization_url", "codex_token_url",
    "codex_responses_url", "codex_redirect_uri", "codex_request_headers"
  )
  configured <- all(vapply(
    required,
    exists,
    logical(1),
    mode = "function",
    envir = fn_env,
    inherits = TRUE
  ))
  # Keep endpoint values out of the diagnostic object. Presence and protocol
  # shape are useful without leaking account, code, or secret material.
  list(
    functions_available = configured,
    callback_configured = if (exists("codex_callback_port", mode = "function", envir = fn_env, inherits = TRUE)) {
      isTRUE(tryCatch(codex_callback_port() == 1455L, error = function(error) FALSE))
    } else {
      FALSE
    },
    originator_configured = if (exists("codex_originator", mode = "function", envir = fn_env, inherits = TRUE)) {
      isTRUE(tryCatch(identical(codex_originator(), "ellmercodex"), error = function(error) FALSE))
    } else {
      FALSE
    }
  )
}

codex_diagnostic_authentication <- function(check_credentials = FALSE) {
  if (!isTRUE(check_credentials)) {
    return(list(checked = FALSE, status = "not_checked"))
  }
  auth <- codex_session_get()
  if (is.null(auth)) {
    auth <- tryCatch(codex_credentials_load(required = FALSE), error = function(error) error)
  }
  if (inherits(auth, "condition")) {
    return(list(checked = TRUE, status = "unavailable"))
  }
  if (is.null(auth)) {
    return(list(checked = TRUE, status = "missing"))
  }
  list(
    checked = TRUE,
    status = if (inherits(auth, "codex_auth")) "present" else "malformed"
  )
}

codex_diagnostic_ellmer <- function() {
  version <- tryCatch(
    as.character(utils::packageVersion("ellmer")),
    error = function(error) NA_character_
  )
  compatible <- tryCatch(
    {
      codex_ellmer_compatibility()
      TRUE
    },
    error = function(error) FALSE
  )
  list(version = version, compatible = compatible)
}

codex_diagnostics <- function(check_credentials = FALSE) {
  if (!is.logical(check_credentials) || length(check_credentials) != 1L || is.na(check_credentials)) {
    codex_auth_abort("`check_credentials` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  dependencies <- codex_diagnostic_dependencies()
  configuration <- codex_diagnostic_configuration()
  authentication <- codex_diagnostic_authentication(check_credentials)
  ellmer <- codex_diagnostic_ellmer()
  dependencies_ok <- all(dependencies[c(
    "ellmer", "httr2", "httpuv", "jsonlite", "openssl", "rlang", "coro"
  )])
  available <- isTRUE(dependencies_ok) && isTRUE(configuration$functions_available) &&
    isTRUE(configuration$callback_configured) && isTRUE(configuration$originator_configured) &&
    isTRUE(ellmer$compatible)
  if (isTRUE(check_credentials)) available <- available && identical(authentication$status, "present")

  list(
    package = "ellmercodex",
    available = available,
    dependencies = dependencies,
    configuration = configuration,
    ellmer = ellmer,
    authentication = authentication,
    model_discovery = list(
      supported = FALSE,
      reason = codex_models_unsupported_reason()
    )
  )
}

#' Check whether the local ellmercodex integration is available.
#'
#' This is an offline check. By default it verifies package dependencies and
#' static configuration only; it does not open a browser, make a request, or
#' inspect a credential store. Set `check_credentials = TRUE` when an explicit
#' credential-presence check is desired.
#'
#' @param check_credentials Whether to inspect this package's own credential
#'   backend. Defaults to `FALSE` to keep ordinary availability checks free of
#'   credential-store I/O.
#' @return A single logical value. The full redacted diagnostic object is
#'   available internally through `codex_diagnostics()`.
#' @examples
#' codex_available()
#' if (interactive()) codex_available(check_credentials = TRUE)
#' @export
codex_available <- function(check_credentials = FALSE) {
  isTRUE(codex_diagnostics(check_credentials = check_credentials)$available)
}

# Package-owned credential storage and credential redaction.
#
# The documented flow issues a client ID per user and workspace, so a fixed
# httr2 OAuth client (and its cache key) no longer fits. The package stores
# its own registration under one directory:
#
# * `host-id`: the stable, opaque `ext_agent_host_id` for this host. It is
#   created before the first sign-in and is never overwritten by an imported
#   credential file.
# * `credentials.json`: the issued client ID, ID token, access and refresh
#   tokens, expiry, and granted scopes. It is written atomically with
#   owner-only permissions (0600 on Unix).
#
# The package never uses an OS keyring and never reads another client's files.

codex_home <- function() {
  path <- Sys.getenv("ELLMERCODEX_HOME", unset = "")
  if (!nzchar(path)) path <- tools::R_user_dir("ellmercodex", which = "config")
  path
}

codex_credentials_path <- function() {
  file.path(codex_home(), "credentials.json")
}

codex_host_id_path <- function() {
  file.path(codex_home(), "host-id")
}

codex_home_create <- function() {
  home <- codex_home()
  if (!dir.exists(home)) {
    ok <- dir.create(home, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    if (!ok && !dir.exists(home)) {
      codex_auth_abort(
        "The ellmercodex credential directory could not be created.",
        "codex_credential_store_error"
      )
    }
  }
  Sys.chmod(home, mode = "0700", use_umask = FALSE)
  invisible(home)
}

codex_write_private <- function(lines, path) {
  codex_home_create()
  temporary <- tempfile(".ellmercodex-", tmpdir = dirname(path))
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  ok <- tryCatch(
    {
      file.create(temporary)
      Sys.chmod(temporary, mode = "0600", use_umask = FALSE)
      writeLines(lines, temporary, useBytes = TRUE)
      file.rename(temporary, path)
    },
    error = function(error) FALSE,
    warning = function(warning) FALSE
  )
  if (!isTRUE(ok)) {
    codex_auth_abort(
      "The ellmercodex credential file could not be written.",
      "codex_credential_store_error"
    )
  }
  Sys.chmod(path, mode = "0600", use_umask = FALSE)
  invisible(path)
}

codex_uuid_v4 <- function() {
  bytes <- openssl::rand_bytes(16L)
  bytes[[7L]] <- as.raw(bitwOr(bitwAnd(as.integer(bytes[[7L]]), 0x0f), 0x40))
  bytes[[9L]] <- as.raw(bitwOr(bitwAnd(as.integer(bytes[[9L]]), 0x3f), 0x80))
  hex <- paste(format(bytes), collapse = "")
  paste(
    substr(hex, 1L, 8L), substr(hex, 9L, 12L), substr(hex, 13L, 16L),
    substr(hex, 17L, 20L), substr(hex, 21L, 32L),
    sep = "-"
  )
}

codex_host_id_valid <- function(value) {
  codex_auth_scalar_character(value) && grepl(
    paste0(
      "^(urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
      "|urn:ietf:params:oauth:jwk-thumbprint:[A-Za-z0-9:._~-]+",
      "|did:key:[A-Za-z0-9]+)$"
    ),
    value,
    perl = TRUE
  )
}

# The host ID is a stable, opaque identifier, not a credential. It is created
# once per host (before the first sign-in) and reused for every registration.
codex_host_id <- function(create = TRUE) {
  path <- codex_host_id_path()
  if (file.exists(path)) {
    value <- tryCatch(trimws(readLines(path, n = 1L, warn = FALSE)), error = function(error) "")
    if (length(value) == 1L && codex_host_id_valid(value)) {
      return(value)
    }
    codex_auth_abort(
      "The stored ellmercodex host ID is malformed; remove the `host-id` file and sign in again.",
      "codex_credential_store_error"
    )
  }
  if (!isTRUE(create)) {
    return(NULL)
  }
  value <- paste0("urn:uuid:", codex_uuid_v4())
  codex_write_private(value, path)
  value
}

codex_store_fields <- c(
  "client_id", "issuer", "sub", "email", "id_token", "access_token",
  "refresh_token", "token_type", "expires_at", "earliest_refresh_at", "scope"
)

codex_store_read <- function() {
  path <- codex_credentials_path()
  if (!file.exists(path)) {
    return(NULL)
  }
  value <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = TRUE),
    error = function(error) NULL
  )
  if (!is.list(value) || !codex_auth_scalar_character(value$client_id)) {
    codex_auth_abort(
      "Stored ellmercodex credentials are malformed; run codex_logout() and codex_login().",
      "codex_credential_store_error"
    )
  }
  value[intersect(names(value), codex_store_fields)]
}

codex_store_write <- function(record) {
  record <- unclass(record)
  record <- record[intersect(names(record), codex_store_fields)]
  record <- Filter(Negate(is.null), record)
  json <- jsonlite::toJSON(record, auto_unbox = TRUE, digits = NA, null = "null")
  codex_write_private(as.character(json), codex_credentials_path())
}

# Keep the registration (issued client ID and ID token hint) so the user can
# reauthorize the same registration, but drop the unusable tokens.
codex_store_clear_tokens <- function() {
  record <- tryCatch(codex_store_read(), error = function(error) NULL)
  if (is.null(record)) {
    return(invisible(FALSE))
  }
  record$access_token <- NULL
  record$refresh_token <- NULL
  record$expires_at <- NULL
  record$earliest_refresh_at <- NULL
  codex_store_write(record)
  invisible(TRUE)
}

# Refresh tokens rotate, so refreshes of the shared credential file are
# serialized across R processes with an atomic lock directory.
codex_with_refresh_lock <- function(code, timeout = 30, stale_after = 120) {
  codex_home_create()
  lock <- file.path(codex_home(), "refresh.lock")
  deadline <- as.numeric(Sys.time()) + timeout
  repeat {
    if (dir.create(lock, showWarnings = FALSE)) break
    age <- as.numeric(Sys.time()) - as.numeric(file.mtime(lock))
    if (is.finite(age) && age > stale_after) {
      unlink(lock, recursive = TRUE, force = TRUE)
      next
    }
    if (as.numeric(Sys.time()) > deadline) {
      codex_auth_abort(
        "Timed out waiting for another R process to refresh the ellmercodex credential.",
        "codex_refresh_error"
      )
    }
    Sys.sleep(0.1)
  }
  on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  force(code)
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
      paste0(
        "([?&](?:code|state|nonce|code_verifier|code_challenge|refresh_token|",
        "access_token|id_token|id_token_hint|login_hint|client_id|",
        "ext_agent_host_id)=)[^&#[:space:]]+"
      ),
      "\\1<redacted>", value,
      ignore.case = TRUE, perl = TRUE
    )
    value <- gsub(
      paste0(
        "((?:access_token|refresh_token|id_token|client_id|account_id|",
        "chatgpt[-_]account[-_]id)[\"']?[[:space:]]*[:=][[:space:]]*)",
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
    value <- gsub("oaiapp_[A-Za-z0-9_-]+", "<redacted-client-id>", value, perl = TRUE)
    value <- gsub(
      "urn:uuid:[0-9a-fA-F-]{36}",
      "<redacted-host-id>", value,
      perl = TRUE
    )
    value <- gsub(
      "(authorization[[:space:]]*:[[:space:]]*)[^,;[:space:]]+",
      "\\1<redacted>", value,
      ignore.case = TRUE, perl = TRUE
    )
    value
  }
  vapply(x, redact_one, character(1), USE.NAMES = FALSE)
}

codex_credentials_valid <- function(value) {
  required_fields <- c("access_token", "refresh_token", "client_id", "expires_at")
  valid_string <- function(x) codex_auth_scalar_character(x)
  expiry <- if (is.list(value)) value$expires_at else NULL
  expiry_valid <- is.null(expiry) ||
    (is.numeric(expiry) && length(expiry) == 1L && (is.finite(expiry) || is.na(expiry)))
  is.list(value) && all(required_fields %in% names(value)) &&
    all(vapply(value[c("access_token", "refresh_token", "client_id")], valid_string, logical(1))) &&
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
  record <- codex_store_read()
  has_tokens <- is.list(record) &&
    codex_auth_scalar_character(record$access_token) &&
    codex_auth_scalar_character(record$refresh_token)
  if (!has_tokens) {
    if (!isTRUE(required)) {
      return(NULL)
    }
    codex_auth_abort(
      "No stored ellmercodex credentials were found; run codex_login().",
      "codex_auth_missing"
    )
  }
  if (is.null(record$expires_at)) record$expires_at <- NA_real_
  auth <- codex_credentials_as_auth(record)
  if (codex_token_expired(auth)) {
    auth <- codex_refresh(auth, persist = TRUE)
  }
  auth
}

codex_oidc_configuration <- function() {
  request <- httr2::request(codex_oidc_discovery_url()) |>
    httr2::req_user_agent(codex_user_agent()) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) NULL)
  if (is.null(response) || httr2::resp_status(response) != 200L) {
    return(NULL)
  }
  value <- tryCatch(httr2::resp_body_json(response), error = function(error) NULL)
  if (is.list(value)) value else NULL
}

codex_revoke <- function(auth) {
  if (!is.list(auth) || !codex_auth_scalar_character(auth$refresh_token) ||
      !codex_auth_scalar_character(auth$client_id)) {
    return(invisible(FALSE))
  }
  endpoint <- codex_oidc_configuration()$revocation_endpoint
  if (!codex_auth_scalar_character(endpoint) || !grepl("^https://", endpoint)) {
    return(invisible(FALSE))
  }
  request <- httr2::request(endpoint) |>
    httr2::req_body_form(
      token = auth$refresh_token,
      token_type_hint = "refresh_token",
      client_id = auth$client_id
    ) |>
    httr2::req_user_agent(codex_user_agent()) |>
    httr2::req_timeout(30) |>
    httr2::req_retry(max_tries = 3L, retry_on_failure = TRUE) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) NULL)
  invisible(!is.null(response) && httr2::resp_status(response) == 200L)
}

# Earlier releases stored a Codex-CLI-compatible token in httr2's cache. It
# cannot be used with the documented flow; logout removes it.
codex_legacy_cache_clear <- function() {
  if (!dir.exists(file.path(httr2::oauth_cache_path(), "ellmercodex"))) {
    return(invisible(FALSE))
  }
  client <- httr2::oauth_client(
    id = "app_EMoamEEZ73f0CkXaXp7hrann",
    token_url = "https://auth.openai.com/oauth/token",
    name = "ellmercodex"
  )
  try(httr2::oauth_cache_clear(client, cache_disk = TRUE), silent = TRUE)
  try(httr2::oauth_cache_clear(client, cache_disk = FALSE), silent = TRUE)
  invisible(TRUE)
}

#' Sign out and remove ellmercodex's stored credential.
#'
#' This function revokes the refresh token with OpenAI (by default), clears
#' the process-local session, and deletes this package's own credential file.
#' It never removes Codex CLI credentials or another application's entries.
#' The host identifier is kept because the documented flow requires it to stay
#' stable for this host.
#'
#' @param revoke Whether to revoke the refresh token at OpenAI's documented
#'   revocation endpoint before deleting it locally. Revocation is best effort:
#'   local credentials are removed even when the network request fails, in
#'   which case a `codex_revocation_warning` warning is signaled.
#' @return `TRUE`, invisibly. The process-local credential is cleared even if
#'   no persistent credential exists.
#' @note To use a different ChatGPT account or workspace, call
#'   `codex_logout()` and then [codex_login()]; the next sign-in creates a new
#'   registration instead of reauthorizing the previous one.
#' @section Conditions:
#' Logout signals no backend details. Storage failures are reported as
#' `codex_credential_store_error` by the explicit login and refresh paths that
#' write credentials.
#' @examplesIf interactive()
#' codex_logout()
#' @export
codex_logout <- function(revoke = TRUE) {
  if (!is.logical(revoke) || length(revoke) != 1L || is.na(revoke)) {
    codex_auth_abort("`revoke` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  candidates <- list(
    codex_session_get(),
    tryCatch(codex_store_read(), error = function(error) NULL)
  )
  if (isTRUE(revoke)) {
    seen <- character()
    for (auth in candidates) {
      token <- if (is.list(auth)) auth$refresh_token else NULL
      if (!codex_auth_scalar_character(token) || token %in% seen) next
      seen <- c(seen, token)
      revoked <- tryCatch(codex_revoke(auth), error = function(error) FALSE)
      if (!isTRUE(revoked)) {
        rlang::warn(
          paste(
            "The refresh token could not be revoked remotely; local credentials",
            "were removed. You can disconnect the app in ChatGPT settings."
          ),
          class = "codex_revocation_warning"
        )
      }
    }
  }
  codex_session_clear()
  unlink(codex_credentials_path(), force = TRUE)
  codex_legacy_cache_clear()
  invisible(TRUE)
}

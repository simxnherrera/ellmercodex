codex_keyring_service <- function() "ellmercodex-poc"

codex_keyring_username <- function() "oauth"

codex_redact <- function(x) {
  x <- as.character(x)
  x <- gsub("Bearer[[:space:]]+[^[:space:]]+", "Bearer <redacted>", x,
    ignore.case = TRUE
  )
  x <- gsub(
    "([?&](code|state|code_verifier)=)[^&#[:space:]]+",
    "\\1<redacted>", x, ignore.case = TRUE, perl = TRUE
  )
  x <- gsub(
    "(access_token|refresh_token|id_token|account_id|chatgpt[-_]account[-_]id)([[:space:]]*[:=][[:space:]]*)[^,}[:space:]]+",
    "\\1\\2<redacted>", x, ignore.case = TRUE, perl = TRUE
  )
  x <- gsub(
    "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
    "<redacted-jwt>", x, perl = TRUE
  )
  x
}

codex_credentials_store <- function(auth) {
  stopifnot(inherits(auth, "codex_auth"))

  payload <- jsonlite::toJSON(
    unclass(auth),
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )

  tryCatch(
    keyring::key_set_with_value(
      service = codex_keyring_service(),
      username = codex_keyring_username(),
      password = payload
    ),
    error = function(error) {
      rlang::abort(
        "Could not save Codex credentials in the OS credential store.",
        class = "codex_credential_store_error"
      )
    }
  )

  invisible(auth)
}

codex_credentials_load <- function(required = TRUE) {
  payload <- tryCatch(
    keyring::key_get(
      service = codex_keyring_service(),
      username = codex_keyring_username()
    ),
    error = function(error) NULL
  )

  if (is.null(payload)) {
    if (!required) return(NULL)
    rlang::abort(
      "No ellmercodex PoC credentials were found; run codex_login().",
      class = "codex_auth_missing"
    )
  }

  value <- tryCatch(
    jsonlite::fromJSON(payload, simplifyVector = TRUE),
    error = function(error) NULL
  )
  required_fields <- c("access_token", "refresh_token", "account_id")
  valid_string <- function(x) is.character(x) && length(x) == 1L && nzchar(x)
  valid <- is.list(value) && all(required_fields %in% names(value)) &&
    all(vapply(value[required_fields], valid_string, logical(1))) &&
    is.numeric(value$expires_at) && length(value$expires_at) == 1L
  if (!valid) {
    rlang::abort(
      "Stored ellmercodex PoC credentials are malformed; run codex_logout() and codex_login().",
      class = "codex_credential_store_error"
    )
  }

  structure(value, class = c("codex_auth", "list"))
}

codex_logout <- function() {
  tryCatch(
    keyring::key_delete(
      service = codex_keyring_service(),
      username = codex_keyring_username()
    ),
    error = function(error) NULL
  )
  invisible(TRUE)
}

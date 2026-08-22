# Credential persistence and redaction.

# The keyring entry is deliberately package-scoped. In particular, this layer
# never reads another client's credential files.
codex_keyring_service <- function() "ellmercodex"

codex_keyring_username <- function() "oauth"

codex_credentials_directory <- function() {
  tools::R_user_dir("ellmercodex", which = "data")
}

codex_credentials_path <- function() {
  file.path(codex_credentials_directory(), "credentials.json.enc")
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

codex_credentials_file_passphrase <- function(required = TRUE) {
  passphrase <- Sys.getenv("ELLMERCODEX_CREDENTIAL_PASSPHRASE", unset = "")
  if (!nzchar(passphrase)) {
    if (isTRUE(required)) {
      codex_auth_abort(
        paste(
          "The encrypted file credential fallback is disabled because",
          "ELLMERCODEX_CREDENTIAL_PASSPHRASE is not set. Use the OS credential store",
          "or set an explicit passphrase before enabling the fallback."
        ),
        "codex_credential_store_error"
      )
    }
    return(NULL)
  }
  passphrase
}

codex_credentials_backend_preference <- function() {
  value <- tolower(Sys.getenv("ELLMERCODEX_CREDENTIAL_BACKEND", unset = "keyring"))
  if (!value %in% c("keyring", "file")) {
    codex_auth_abort(
      "ELLMERCODEX_CREDENTIAL_BACKEND must be `keyring` or `file`.",
      "codex_credential_store_error"
    )
  }
  value
}

codex_keyring_available <- function() {
  isTRUE(requireNamespace("keyring", quietly = TRUE))
}

codex_file_backend_enabled <- function() {
  identical(codex_credentials_backend_preference(), "file") ||
    (!codex_keyring_available() && !is.null(codex_credentials_file_passphrase(required = FALSE)))
}

codex_credentials_keyring_store <- function(payload) {
  tryCatch(
    keyring::key_set_with_value(
      service = codex_keyring_service(),
      username = codex_keyring_username(),
      password = payload
    ),
    error = function(error) {
      codex_auth_abort(
        "Could not save Codex credentials in the OS credential store.",
        "codex_credential_store_error"
      )
    }
  )
  invisible(TRUE)
}

codex_credentials_keyring_load <- function() {
  tryCatch(
    keyring::key_get(
      service = codex_keyring_service(),
      username = codex_keyring_username()
    ),
    error = function(error) {
      # A missing key and an unavailable backend are intentionally represented
      # by the same NULL value here; callers decide whether an explicit file
      # fallback is enabled and never expose backend error text.
      NULL
    }
  )
}

codex_credentials_keyring_delete <- function() {
  if (!codex_keyring_available()) {
    return(invisible(TRUE))
  }
  tryCatch(
    keyring::key_delete(
      service = codex_keyring_service(),
      username = codex_keyring_username()
    ),
    error = function(error) NULL
  )
  invisible(TRUE)
}

codex_file_keys <- function(passphrase, salt, rounds = 64L) {
  # Derive independent encryption and authentication keys from a random salt.
  # bcrypt_pbkdf makes offline passphrase guessing more expensive than a
  # single fast digest.
  derived <- openssl::bcrypt_pbkdf(
    password = passphrase,
    salt = salt,
    rounds = rounds,
    size = 64L
  )
  list(encryption = derived[seq_len(32L)], authentication = derived[33L:64L])
}

codex_credentials_file_mac <- function(version, rounds, salt, iv, ciphertext, key) {
  # Authenticate the complete ciphertext envelope before attempting decryption.
  metadata <- charToRaw(sprintf("ellmercodex:%d:%d:", version, rounds))
  codex_base64url_encode(
    openssl::sha256(c(metadata, salt, iv, ciphertext), key = key)
  )
}

codex_credentials_file_encrypt <- function(payload, passphrase) {
  version <- 2L
  rounds <- 64L
  salt <- openssl::rand_bytes(16L)
  keys <- codex_file_keys(passphrase, salt, rounds)
  encrypted <- openssl::aes_gcm_encrypt(
    charToRaw(payload),
    key = keys$encryption
  )
  iv <- attr(encrypted, "iv")
  ciphertext <- unclass(encrypted)
  envelope <- list(
    version = version,
    kdf = "bcrypt_pbkdf",
    rounds = rounds,
    salt = codex_base64url_encode(salt),
    iv = codex_base64url_encode(iv),
    ciphertext = codex_base64url_encode(ciphertext),
    mac = codex_credentials_file_mac(
      version,
      rounds,
      salt,
      iv,
      ciphertext,
      keys$authentication
    )
  )
  jsonlite::toJSON(envelope, auto_unbox = TRUE)
}

codex_credentials_file_decrypt <- function(payload, passphrase) {
  envelope <- tryCatch(jsonlite::fromJSON(payload, simplifyVector = TRUE), error = function(error) NULL)
  valid <- is.list(envelope) && identical(as.integer(envelope$version), 2L) &&
    identical(envelope$kdf, "bcrypt_pbkdf") &&
    identical(as.integer(envelope$rounds), 64L) &&
    codex_auth_scalar_character(envelope$salt) &&
    codex_auth_scalar_character(envelope$iv) &&
    codex_auth_scalar_character(envelope$ciphertext) &&
    codex_auth_scalar_character(envelope$mac)
  if (!valid) {
    return(NULL)
  }
  tryCatch(
    {
      salt <- codex_base64url_decode(envelope$salt)
      keys <- codex_file_keys(passphrase, salt, as.integer(envelope$rounds))
      iv <- codex_base64url_decode(envelope$iv)
      encrypted <- codex_base64url_decode(envelope$ciphertext)
      expected_mac <- codex_credentials_file_mac(
        2L,
        64L,
        salt,
        iv,
        encrypted,
        keys$authentication
      )
      if (!identical(expected_mac, envelope$mac)) {
        return(NULL)
      }
      attr(encrypted, "iv") <- iv
      plaintext <- rawToChar(
        openssl::aes_gcm_decrypt(encrypted, key = keys$encryption)
      )
      plaintext
    },
    error = function(error) NULL
  )
}

codex_credentials_file_store <- function(payload) {
  passphrase <- codex_credentials_file_passphrase(required = TRUE)
  directory <- codex_credentials_directory()
  path <- codex_credentials_path()
  if (!dir.exists(directory) && !dir.create(directory, recursive = TRUE, mode = "0700")) {
    codex_auth_abort(
      "Could not create the private ellmercodex credential directory.",
      "codex_credential_store_error"
    )
  }
  # Tighten permissions even when the directory existed before this call.
  try(Sys.chmod(directory, mode = "0700"), silent = TRUE)
  encrypted <- codex_credentials_file_encrypt(payload, passphrase)
  temporary <- tempfile("credentials-", tmpdir = directory, fileext = ".tmp")
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  ok <- tryCatch(
    {
      writeLines(encrypted, temporary, useBytes = TRUE)
      TRUE
    },
    error = function(error) FALSE
  )
  if (!isTRUE(ok)) {
    codex_auth_abort(
      "Could not save the encrypted ellmercodex credential fallback.",
      "codex_credential_store_error"
    )
  }
  try(Sys.chmod(temporary, mode = "0600"), silent = TRUE)
  if (!file.rename(temporary, path)) {
    # Windows can reject rename-overwrite; remove only this exact package file
    # before a retry. No broad or recursive deletion is used.
    if (file.exists(path)) unlink(path, force = TRUE)
    if (!file.rename(temporary, path)) {
      codex_auth_abort(
        "Could not finalize the encrypted ellmercodex credential fallback.",
        "codex_credential_store_error"
      )
    }
  }
  try(Sys.chmod(path, mode = "0600"), silent = TRUE)
  invisible(TRUE)
}

codex_credentials_file_load <- function() {
  path <- codex_credentials_path()
  if (!file.exists(path)) {
    return(NULL)
  }
  passphrase <- codex_credentials_file_passphrase(required = TRUE)
  payload <- tryCatch(
    paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(error) NULL
  )
  if (is.null(payload)) {
    return(NULL)
  }
  codex_credentials_file_decrypt(payload, passphrase)
}

codex_credentials_file_delete <- function() {
  path <- codex_credentials_path()
  if (file.exists(path)) unlink(path, force = TRUE)
  invisible(TRUE)
}

codex_credentials_payload <- function(auth) {
  if (!inherits(auth, "codex_auth") || !codex_credentials_valid(auth)) {
    codex_auth_abort("The credential cannot be stored because it is malformed.", "codex_credential_store_error")
  }
  jsonlite::toJSON(unclass(auth), auto_unbox = TRUE, null = "null", na = "null", digits = NA)
}

codex_credentials_store <- function(auth) {
  payload <- codex_credentials_payload(auth)
  preference <- codex_credentials_backend_preference()

  if (identical(preference, "keyring")) {
    if (!codex_keyring_available()) {
      # A missing keyring package is never permission to write plaintext. The
      # encrypted fallback requires an explicit passphrase.
      codex_credentials_file_store(payload)
    } else {
      stored <- tryCatch(
        codex_credentials_keyring_store(payload),
        error = function(error) error
      )
      if (inherits(stored, "condition")) {
        # Some OS keyring backends are installed but unavailable (for example,
        # in a headless session). An explicitly supplied passphrase permits a
        # secure encrypted fallback; without one, retain the sanitized keyring
        # condition and never write plaintext.
        if (!is.null(codex_credentials_file_passphrase(required = FALSE))) {
          # Avoid leaving an older keyring value that would win on the next
          # load after this fallback succeeds.
          codex_credentials_keyring_delete()
          codex_credentials_file_store(payload)
        } else {
          codex_auth_abort(
            "Could not save Codex credentials in the OS credential store.",
            "codex_credential_store_error"
          )
        }
      }
    }
  } else {
    codex_credentials_file_store(payload)
  }
  invisible(auth)
}

codex_credentials_load <- function(required = TRUE) {
  if (!is.logical(required) || length(required) != 1L || is.na(required)) {
    codex_auth_abort("`required` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  preference <- codex_credentials_backend_preference()
  payload <- NULL

  if (identical(preference, "keyring")) {
    if (codex_keyring_available()) {
      payload <- codex_credentials_keyring_load()
      if (is.null(payload) && file.exists(codex_credentials_path()) &&
            !is.null(codex_credentials_file_passphrase(required = FALSE))) {
        payload <- codex_credentials_file_load()
      }
    } else if (isTRUE(required) || codex_file_backend_enabled()) {
      payload <- codex_credentials_file_load()
    }
  } else {
    payload <- codex_credentials_file_load()
  }

  if (is.null(payload)) {
    if (!isTRUE(required)) {
      return(NULL)
    }
    codex_auth_abort(
      "No ellmercodex credentials were found; run codex_login().",
      "codex_auth_missing"
    )
  }

  value <- tryCatch(jsonlite::fromJSON(payload, simplifyVector = TRUE), error = function(error) NULL)
  if (!codex_credentials_valid(value)) {
    codex_auth_abort(
      "Stored ellmercodex credentials are malformed; run codex_logout() and codex_login().",
      "codex_credential_store_error"
    )
  }
  codex_credentials_as_auth(value)
}

#' Remove only ellmercodex's stored Codex credential.
#'
#' This function touches only the package-scoped keyring entry (or the
#' explicitly enabled encrypted fallback file). It never removes Codex CLI
#' credentials or other applications' entries.
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
  # Logout remains best-effort: a user should be able to clear one backend even
  # if the other backend is unavailable. No backend error text is exposed.
  codex_session_clear()
  if (codex_keyring_available()) codex_credentials_keyring_delete()
  try(codex_credentials_file_delete(), silent = TRUE)
  invisible(TRUE)
}

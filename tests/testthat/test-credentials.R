testthat::test_that("redaction removes OAuth material without exposing it", {
  value <- paste(
    "Authorization: Bearer fixture-secret",
    "?code=fixture-code&state=fixture-state",
    "access_token=fixture-access account_id: fixture-account",
    "eyJheader.payload.signature",
    sep = " "
  )
  safe <- codex_redact(value)
  testthat::expect_false(grepl("fixture-secret|fixture-code|fixture-state|fixture-access|fixture-account", safe))
  testthat::expect_match(safe, "<redacted>")
})

testthat::test_that("credential payloads validate package auth objects", {
  auth <- fake_codex_auth()
  payload <- codex_credentials_payload(auth)
  testthat::expect_type(payload, "character")
  testthat::expect_match(payload, "fixture-access-token")
  testthat::expect_true(codex_credentials_valid(jsonlite::fromJSON(payload, simplifyVector = TRUE)))

  encrypted <- codex_credentials_file_encrypt(payload, "fixture-passphrase")
  testthat::expect_false(grepl("fixture-access-token|fixture-refresh-token", encrypted, fixed = FALSE))
  decrypted <- codex_credentials_file_decrypt(encrypted, "fixture-passphrase")
  testthat::expect_equal(decrypted, as.character(payload))
  testthat::expect_null(codex_credentials_file_decrypt(encrypted, "wrong-passphrase"))

  tampered <- jsonlite::fromJSON(encrypted, simplifyVector = TRUE)
  tampered$mac <- paste0("A", tampered$mac)
  tampered <- jsonlite::toJSON(tampered, auto_unbox = TRUE)
  testthat::expect_null(codex_credentials_file_decrypt(tampered, "fixture-passphrase"))
})

testthat::test_that("credential logout is package scoped and explicit", {
  testthat::expect_identical(codex_keyring_service(), "ellmercodex")
  testthat::expect_identical(codex_keyring_username(), "oauth")
  # No credential APIs are called here: logout behavior is exercised by the
  # implementation's exact service/path helpers, while CI remains offline.
  testthat::expect_match(codex_credentials_path(), "ellmercodex")
})

testthat::test_that("encrypted file storage round-trips only in a package path", {
  directory <- tempfile("ellmercodex-credentials-")
  path <- file.path(directory, "credentials.json.enc")
  on.exit(unlink(directory, recursive = TRUE, force = TRUE), add = TRUE)
  old_backend <- Sys.getenv("ELLMERCODEX_CREDENTIAL_BACKEND", unset = NA_character_)
  old_passphrase <- Sys.getenv("ELLMERCODEX_CREDENTIAL_PASSPHRASE", unset = NA_character_)
  on.exit({
    if (is.na(old_backend)) {
      Sys.unsetenv("ELLMERCODEX_CREDENTIAL_BACKEND")
    } else {
      Sys.setenv(ELLMERCODEX_CREDENTIAL_BACKEND = old_backend)
    }
    if (is.na(old_passphrase)) {
      Sys.unsetenv("ELLMERCODEX_CREDENTIAL_PASSPHRASE")
    } else {
      Sys.setenv(ELLMERCODEX_CREDENTIAL_PASSPHRASE = old_passphrase)
    }
  }, add = TRUE)
  Sys.setenv(
    ELLMERCODEX_CREDENTIAL_BACKEND = "file",
    ELLMERCODEX_CREDENTIAL_PASSPHRASE = "fixture-passphrase"
  )
  testthat::local_mocked_bindings(
    codex_credentials_directory = function() directory,
    codex_credentials_path = function() path,
    .package = "ellmercodex"
  )

  auth <- fake_codex_auth()
  codex_credentials_store(auth)
  testthat::expect_true(file.exists(path))
  loaded <- codex_credentials_load()
  testthat::expect_s3_class(loaded, "codex_auth")
  testthat::expect_equal(unclass(loaded), unclass(auth), tolerance = 1e-5)
  testthat::expect_false(grepl(
    "fixture-access-token|fixture-refresh-token",
    paste(readLines(path, warn = FALSE), collapse = ""),
    perl = TRUE
  ))

  codex_credentials_file_delete()
  testthat::expect_false(file.exists(path))
})

testthat::test_that("logout clears the process-local session", {
  codex_session_set(fake_codex_auth(), persist = FALSE)
  testthat::local_mocked_bindings(
    codex_keyring_available = function() FALSE,
    codex_credentials_file_delete = function() invisible(TRUE),
    .package = "ellmercodex"
  )

  ellmercodex::codex_logout()
  testthat::expect_null(codex_session_get())
})

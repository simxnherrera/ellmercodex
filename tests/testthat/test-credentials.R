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

testthat::test_that("credential objects validate the fields needed by the transport", {
  auth <- fake_codex_auth()
  testthat::expect_true(codex_credentials_valid(unclass(auth)))
  testthat::expect_s3_class(codex_credentials_as_auth(unclass(auth)), "codex_auth")
  testthat::expect_false(codex_credentials_valid(list(access_token = "fixture")))
})

testthat::test_that("httr2 encrypts the disk cache and reuses a cached token", {
  cache_directory <- tempfile("ellmercodex-httr2-cache-")
  on.exit(unlink(cache_directory, recursive = TRUE, force = TRUE), add = TRUE)
  old_cache <- Sys.getenv("HTTR2_OAUTH_CACHE", unset = NA_character_)
  on.exit({
    if (is.na(old_cache)) {
      Sys.unsetenv("HTTR2_OAUTH_CACHE")
    } else {
      Sys.setenv(HTTR2_OAUTH_CACHE = old_cache)
    }
  }, add = TRUE)
  Sys.setenv(HTTR2_OAUTH_CACHE = cache_directory)

  access_token <- paste(
    "header",
    codex_base64url_encode(charToRaw(
      '{"https://api.openai.com/auth":{"chatgpt_account_id":"fixture-account"}}'
    )),
    "signature",
    sep = "."
  )
  calls <- 0L
  client <- httr2::oauth_client(
    id = "fixture-client",
    token_url = "https://example.invalid/token",
    name = "ellmercodex"
  )
  flow <- function(client) {
    calls <<- calls + 1L
    httr2::oauth_token(
      access_token = access_token,
      refresh_token = "fixture-refresh",
      expires_in = 3600
    )
  }

  first <- httr2::oauth_token_cached(client, flow, cache_disk = TRUE)
  second <- httr2::oauth_token_cached(client, flow, cache_disk = TRUE)

  testthat::expect_identical(calls, 1L)
  testthat::expect_identical(first$access_token, second$access_token)
  files <- list.files(cache_directory, recursive = TRUE, full.names = TRUE, include.dirs = FALSE)
  token_files <- files[grepl("token\\.rds\\.enc$", files)]
  testthat::expect_length(token_files, 1L)
  testthat::expect_gt(file.info(token_files[[1L]])$size, 0)

  httr2::oauth_cache_clear(client, cache_disk = TRUE)
  testthat::expect_length(list.files(cache_directory, recursive = TRUE, include.dirs = FALSE), 0L)
})

testthat::test_that("the default package credential path uses httr2 without Keychain", {
  auth <- fake_codex_auth()
  calls <- list()
  testthat::local_mocked_bindings(
    codex_oauth_token_cached = function(cache_disk, reauth, allow_interactive, timeout = 300, cache_key = NULL) {
      calls <<- list(
        cache_disk = cache_disk,
        reauth = reauth,
        allow_interactive = allow_interactive,
        timeout = timeout
      )
      list(
        access_token = auth$access_token,
        refresh_token = auth$refresh_token,
        expires_at = auth$expires_at,
        id_token = auth$id_token
      )
    },
    codex_auth_from_tokens = function(tokens, previous = NULL) auth,
    .package = "ellmercodex"
  )

  loaded <- codex_credentials_load()
  testthat::expect_s3_class(loaded, "codex_auth")
  testthat::expect_identical(calls$cache_disk, TRUE)
  testthat::expect_identical(calls$reauth, FALSE)
  testthat::expect_identical(calls$allow_interactive, FALSE)
})

testthat::test_that("missing cached credentials do not trigger browser auth", {
  testthat::local_mocked_bindings(
    codex_oauth_token_cached = function(...) {
      codex_auth_abort("No stored credentials.", "codex_auth_missing")
    },
    .package = "ellmercodex"
  )

  testthat::expect_null(codex_credentials_load(required = FALSE))
  testthat::expect_error(codex_credentials_load(), class = "codex_auth_missing")
})

testthat::test_that("logout clears the process-local session and httr2 cache", {
  codex_session_set(fake_codex_auth(), persist = FALSE)
  cache_directory <- tempfile("ellmercodex-logout-cache-")
  on.exit(unlink(cache_directory, recursive = TRUE, force = TRUE), add = TRUE)
  old_cache <- Sys.getenv("HTTR2_OAUTH_CACHE", unset = NA_character_)
  on.exit({
    if (is.na(old_cache)) {
      Sys.unsetenv("HTTR2_OAUTH_CACHE")
    } else {
      Sys.setenv(HTTR2_OAUTH_CACHE = old_cache)
    }
  }, add = TRUE)
  Sys.setenv(HTTR2_OAUTH_CACHE = cache_directory)

  ellmercodex::codex_logout()
  testthat::expect_null(codex_session_get())
})

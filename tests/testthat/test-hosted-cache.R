testthat::test_that("a fresh R process reuses and rotates the persistent credential", {
  testthat::skip_if_not_installed("callr")
  testthat::skip_if_not_installed("pkgload")

  cache_directory <- tempfile("ellmercodex-hosted-cache-")
  on.exit(unlink(cache_directory, recursive = TRUE, force = TRUE), add = TRUE)
  old_cache <- Sys.getenv("HTTR2_OAUTH_CACHE", unset = NA_character_)
  on.exit({
    if (is.na(old_cache)) Sys.unsetenv("HTTR2_OAUTH_CACHE")
    else Sys.setenv(HTTR2_OAUTH_CACHE = old_cache)
  }, add = TRUE)
  Sys.setenv(HTTR2_OAUTH_CACHE = cache_directory)

  access_token <- paste(
    "header",
    fixture_base64url('{"https://api.openai.com/auth":{"chatgpt_account_id":"fixture-account"}}'),
    "signature",
    sep = "."
  )
  testthat::local_mocked_bindings(
    codex_oauth_flow = function(...) httr2::oauth_token(
      access_token = access_token,
      refresh_token = "fixture-original-refresh",
      expires_in = 0
    ),
    .package = "ellmercodex"
  )
  codex_oauth_token_cached(cache_disk = TRUE, reauth = TRUE, allow_interactive = TRUE)

  package_root <- testthat::test_path("../..")
  result <- callr::r(
    function(package_root, cache_directory, access_token) {
      Sys.setenv(HTTR2_OAUTH_CACHE = cache_directory)
      if (file.exists(file.path(package_root, "DESCRIPTION"))) {
        pkgload::load_all(package_root, quiet = TRUE)
      } else {
        library(ellmercodex)
      }
      refresh_calls <- 0L
      refreshed <- httr2::with_mocked_responses(
        function(req) {
          refresh_calls <<- refresh_calls + 1L
          httr2::response_json(body = list(
            access_token = access_token,
            refresh_token = "fixture-rotated-refresh",
            expires_in = 3600
          ))
        },
        ellmercodex:::codex_credentials_load()
      )
      reread <- ellmercodex:::codex_credentials_load()
      c(
        refreshed = identical(refreshed$refresh_token, "fixture-rotated-refresh"),
        stored = identical(reread$refresh_token, "fixture-rotated-refresh"),
        one_refresh = identical(refresh_calls, 1L)
      )
    },
    args = list(package_root, cache_directory, access_token),
    show = FALSE
  )
  testthat::expect_identical(result, c(refreshed = TRUE, stored = TRUE, one_refresh = TRUE))

  testthat::expect_identical(codex_credentials_load()$refresh_token, "fixture-rotated-refresh")
  ellmercodex::codex_logout()
  testthat::expect_length(
    list.files(cache_directory, recursive = TRUE, pattern = "-token\\.rds\\.enc$"),
    0L
  )
})

testthat::test_that("httr2 1.3.0 prunes old encrypted token files", {
  testthat::skip_if_not_installed("callr")
  cache_directory <- tempfile("ellmercodex-prune-cache-")
  on.exit(unlink(cache_directory, recursive = TRUE, force = TRUE), add = TRUE)
  old_cache <- Sys.getenv("HTTR2_OAUTH_CACHE", unset = NA_character_)
  on.exit({
    if (is.na(old_cache)) Sys.unsetenv("HTTR2_OAUTH_CACHE")
    else Sys.setenv(HTTR2_OAUTH_CACHE = old_cache)
  }, add = TRUE)
  Sys.setenv(HTTR2_OAUTH_CACHE = cache_directory)

  client <- httr2::oauth_client(
    id = "fixture-client",
    token_url = "https://example.invalid/token",
    name = "ellmercodex"
  )
  httr2::oauth_token_cached(
    client,
    function(client) httr2::oauth_token("fixture-access", expires_in = 3600),
    cache_disk = TRUE
  )
  token_file <- list.files(cache_directory, recursive = TRUE, full.names = TRUE,
                           pattern = "-token\\.rds\\.enc$")
  testthat::expect_length(token_file, 1L)
  Sys.setFileTime(token_file, Sys.time() - 31 * 86400)
  still_exists <- callr::r(
    function(cache_directory, token_file) {
      Sys.setenv(HTTR2_OAUTH_CACHE = cache_directory)
      library(httr2)
      file.exists(token_file)
    },
    args = list(cache_directory, token_file),
    show = FALSE
  )
  testthat::expect_identical(still_exists, FALSE)
})

testthat::test_that("process-only login leaves no disk credential", {
  cache_directory <- tempfile("ellmercodex-memory-cache-")
  on.exit(unlink(cache_directory, recursive = TRUE, force = TRUE), add = TRUE)
  on.exit(codex_session_clear(), add = TRUE)
  old_cache <- Sys.getenv("HTTR2_OAUTH_CACHE", unset = NA_character_)
  on.exit({
    if (is.na(old_cache)) Sys.unsetenv("HTTR2_OAUTH_CACHE")
    else Sys.setenv(HTTR2_OAUTH_CACHE = old_cache)
  }, add = TRUE)
  Sys.setenv(HTTR2_OAUTH_CACHE = cache_directory)

  access_token <- paste(
    "header",
    fixture_base64url('{"https://api.openai.com/auth":{"chatgpt_account_id":"fixture-account"}}'),
    "signature",
    sep = "."
  )
  testthat::local_mocked_bindings(
    codex_oauth_flow = function(...) httr2::oauth_token(
      access_token = access_token,
      refresh_token = "fixture-memory-refresh",
      expires_in = 3600
    ),
    .package = "ellmercodex"
  )

  auth <- ellmercodex::codex_login(persist = FALSE)
  testthat::expect_identical(codex_session_get(), auth)
  testthat::expect_identical(codex_session_persists(), FALSE)
  testthat::expect_length(list.files(cache_directory, recursive = TRUE), 0L)
})

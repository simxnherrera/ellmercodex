testthat::test_that("a fresh R process reuses and rotates the persistent credential", {
  testthat::skip_if_not_installed("callr")
  testthat::skip_if_not_installed("pkgload")
  home <- local_codex_home()

  stale <- fake_codex_auth()
  stale$expires_at <- as.numeric(Sys.time()) - 10
  codex_store_write(stale)
  host_id <- codex_host_id()

  package_root <- testthat::test_path("../..")
  result <- callr::r(
    function(package_root, home) {
      Sys.setenv(ELLMERCODEX_HOME = home)
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
            access_token = "fixture-rotated-access",
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
    args = list(package_root, home),
    show = FALSE
  )
  testthat::expect_identical(result, c(refreshed = TRUE, stored = TRUE, one_refresh = TRUE))

  testthat::expect_identical(codex_credentials_load()$refresh_token, "fixture-rotated-refresh")
  testthat::expect_identical(codex_host_id(create = FALSE), host_id)
  ellmercodex::codex_logout(revoke = FALSE)
  testthat::expect_false(file.exists(file.path(home, "credentials.json")))
})

testthat::test_that("an imported credential file keeps this host's ID", {
  home <- local_codex_home()
  host_id <- codex_host_id()
  # Simulate copying a credential file from another machine over SSH.
  writeLines(
    as.character(jsonlite::toJSON(unclass(fake_codex_auth()), auto_unbox = TRUE)),
    file.path(home, "credentials.json")
  )
  testthat::expect_s3_class(codex_credentials_load(), "codex_auth")
  testthat::expect_identical(codex_host_id(), host_id)
})

testthat::test_that("process-only login leaves no disk credential", {
  home <- local_codex_home()
  testthat::local_mocked_bindings(
    codex_oauth_flow = function(registration = NULL, timeout = 300) {
      codex_host_id(create = TRUE)
      list(
        client_id = "oaiapp_fixtureclient",
        tokens = fixture_token_response(),
        claims = list(sub = "fixture-subject")
      )
    },
    .package = "ellmercodex"
  )

  auth <- ellmercodex::codex_login(persist = FALSE)
  testthat::expect_identical(codex_session_get(), auth)
  testthat::expect_identical(codex_session_persists(), FALSE)
  testthat::expect_identical(list.files(home, recursive = TRUE), "host-id")
})

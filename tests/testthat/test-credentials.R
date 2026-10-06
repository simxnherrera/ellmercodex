testthat::test_that("redaction removes OAuth material without exposing it", {
  value <- paste(
    "Authorization: Bearer fixture-secret",
    "?code=fixture-code&state=fixture-state&id_token_hint=fixture-hint&nonce=fixture-nonce",
    "access_token=fixture-access client_id: oaiapp_fixtureclient",
    "host urn:uuid:00000000-0000-4000-8000-000000000000",
    "eyJheader.payload.signature",
    sep = " "
  )
  safe <- codex_redact(value)
  testthat::expect_false(grepl(
    "fixture-secret|fixture-code|fixture-state|fixture-hint|fixture-nonce|fixture-access|oaiapp_fixtureclient|00000000-0000",
    safe
  ))
  testthat::expect_match(safe, "<redacted>")
})

testthat::test_that("credential objects validate the fields needed by the transport", {
  auth <- fake_codex_auth()
  testthat::expect_true(codex_credentials_valid(unclass(auth)))
  testthat::expect_s3_class(codex_credentials_as_auth(unclass(auth)), "codex_auth")
  testthat::expect_false(codex_credentials_valid(list(access_token = "fixture")))
  legacy <- unclass(auth)
  legacy$client_id <- NULL
  legacy$account_id <- "fixture-account"
  testthat::expect_false(codex_credentials_valid(legacy))
})

testthat::test_that("the host ID is created once, stable, and opaque", {
  home <- local_codex_home()
  testthat::expect_null(codex_host_id(create = FALSE))
  first <- codex_host_id()
  testthat::expect_match(
    first,
    "^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
  )
  testthat::expect_identical(codex_host_id(), first)
  testthat::expect_true(codex_host_id_valid("urn:ietf:params:oauth:jwk-thumbprint:sha-256:abc_DEF-123"))
  testthat::expect_true(codex_host_id_valid("did:key:z6MkfixtureKey"))
  testthat::expect_false(codex_host_id_valid("person@example.com"))

  writeLines("person@example.com", file.path(home, "host-id"))
  testthat::expect_error(codex_host_id(), class = "codex_credential_store_error")
})

testthat::test_that("the credential store is atomic, private, and round-trips", {
  home <- local_codex_home()
  codex_store_write(fake_codex_auth())
  path <- file.path(home, "credentials.json")
  if (.Platform$OS.type == "unix") {
    testthat::expect_identical(format(file.info(path)$mode), "600")
    testthat::expect_identical(format(file.info(home)$mode), "700")
  }
  testthat::expect_length(list.files(home, pattern = "^\\.ellmercodex-", all.files = TRUE), 0L)
  stored <- codex_store_read()
  testthat::expect_identical(stored$client_id, "oaiapp_fixtureclient")
  loaded <- codex_credentials_load()
  testthat::expect_s3_class(loaded, "codex_auth")
  testthat::expect_identical(loaded$access_token, "fixture-access-token")

  writeLines("{not json", path)
  testthat::expect_error(codex_store_read(), class = "codex_credential_store_error")
})

testthat::test_that("missing stored credentials do not trigger browser auth", {
  local_codex_home()
  testthat::local_mocked_bindings(
    codex_oauth_flow = function(...) stop("browser auth must not start"),
    .package = "ellmercodex"
  )
  testthat::expect_null(codex_credentials_load(required = FALSE))
  testthat::expect_error(codex_credentials_load(), class = "codex_auth_missing")
  testthat::expect_false(ellmercodex::codex_account()$authenticated)
})

testthat::test_that("logout revokes the refresh token and keeps the host ID", {
  home <- local_codex_home()
  host_id <- codex_host_id()
  codex_store_write(fake_codex_auth())
  codex_session_set(fake_codex_auth(), persist = TRUE)
  testthat::local_mocked_bindings(
    codex_oidc_configuration = function() list(revocation_endpoint = "https://auth.openai.com/oauth/revoke"),
    .package = "ellmercodex"
  )
  seen <- list()
  httr2::with_mocked_responses(
    function(req) {
      seen[[length(seen) + 1L]] <<- req
      httr2::response(200L)
    },
    ellmercodex::codex_logout()
  )
  testthat::expect_length(seen, 1L)
  testthat::expect_identical(seen[[1L]]$url, "https://auth.openai.com/oauth/revoke")
  form <- seen[[1L]]$body$data
  testthat::expect_identical(utils::URLdecode(unclass(form$token)), "fixture-refresh-token")
  testthat::expect_identical(utils::URLdecode(unclass(form$token_type_hint)), "refresh_token")
  testthat::expect_identical(utils::URLdecode(unclass(form$client_id)), "oaiapp_fixtureclient")
  testthat::expect_null(codex_session_get())
  testthat::expect_false(file.exists(file.path(home, "credentials.json")))
  testthat::expect_identical(codex_host_id(create = FALSE), host_id)
})

testthat::test_that("logout still removes local credentials when revocation fails", {
  home <- local_codex_home()
  codex_store_write(fake_codex_auth())
  testthat::local_mocked_bindings(
    codex_oidc_configuration = function() NULL,
    .package = "ellmercodex"
  )
  testthat::expect_warning(ellmercodex::codex_logout(), class = "codex_revocation_warning")
  testthat::expect_false(file.exists(file.path(home, "credentials.json")))

  codex_store_write(fake_codex_auth())
  testthat::expect_no_warning(ellmercodex::codex_logout(revoke = FALSE))
  testthat::expect_false(file.exists(file.path(home, "credentials.json")))
  testthat::expect_error(ellmercodex::codex_logout(revoke = NA), class = "codex_auth_argument_error")
})

testthat::test_that("logout removes the legacy httr2 token cache", {
  home <- local_codex_home()
  client <- httr2::oauth_client(
    id = "app_EMoamEEZ73f0CkXaXp7hrann",
    token_url = "https://auth.openai.com/oauth/token",
    name = "ellmercodex"
  )
  suppressMessages(httr2::oauth_token_cached(
    client,
    function(client) httr2::oauth_token("fixture-legacy", expires_in = 3600),
    cache_disk = TRUE
  ))
  testthat::expect_length(list.files(file.path(home, "httr2"), recursive = TRUE), 1L)
  ellmercodex::codex_logout(revoke = FALSE)
  testthat::expect_length(list.files(file.path(home, "httr2"), recursive = TRUE), 0L)
})

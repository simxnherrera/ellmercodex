fixture_form <- function(value) {
  utils::URLdecode(unclass(value))
}

fixture_query <- function(url) {
  httr2::url_parse(url)$query
}

fixture_signing_key <- function() {
  key <- openssl::rsa_keygen(2048L)
  jwk <- jsonlite::fromJSON(jose::write_jwk(key$pubkey), simplifyVector = FALSE)
  jwk$kid <- "fixture-kid"
  jwk$alg <- "RS256"
  list(key = key, jwk = jwk)
}

fixture_id_token <- function(signing, ...) {
  claims <- utils::modifyList(
    list(
      iss = "https://auth.openai.com",
      aud = "oaiapp_fixtureclient",
      sub = "fixture-subject",
      email = "person@example.com",
      nonce = "fixture-nonce",
      iat = as.numeric(Sys.time()),
      exp = as.numeric(Sys.time()) + 3600
    ),
    list(...)
  )
  jose::jwt_encode_sig(
    do.call(jose::jwt_claim, claims),
    signing$key,
    header = list(kid = "fixture-kid")
  )
}

local_fixture_jwks <- function(signing, env = parent.frame()) {
  testthat::local_mocked_bindings(
    codex_oidc_configuration = function() list(
      issuer = "https://auth.openai.com",
      jwks_uri = "https://auth.openai.com/.well-known/jwks.json",
      revocation_endpoint = "https://auth.openai.com/oauth/revoke"
    ),
    codex_jwks = function(refresh = FALSE) list(signing$jwk),
    .package = "ellmercodex",
    .env = env
  )
  session <- getFromNamespace(".codex_session", "ellmercodex")
  session$oidc <- NULL
  fixture_defer(session$oidc <- NULL, envir = env)
}

testthat::test_that("token responses become credentials bound to the issued client", {
  auth <- codex_auth_from_tokens(
    fixture_token_response(),
    client_id = "oaiapp_fixtureclient",
    claims = list(iss = "https://auth.openai.com", sub = "fixture-subject", email = "person@example.com")
  )
  testthat::expect_identical(auth$client_id, "oaiapp_fixtureclient")
  testthat::expect_identical(auth$sub, "fixture-subject")
  testthat::expect_true(codex_scope_granted(auth$scope))
  testthat::expect_false(codex_token_expired(auth))
  testthat::expect_true(codex_token_expired(auth, skew = 0, now = auth$expires_at))
  testthat::expect_error(
    codex_auth_from_tokens(fixture_token_response()),
    class = "codex_token_exchange_error"
  )

  rotated <- codex_auth_from_tokens(
    fixture_token_response(refresh_token = NULL, id_token = NULL, access_token = "fixture-new"),
    previous = auth
  )
  testthat::expect_identical(rotated$client_id, "oaiapp_fixtureclient")
  testthat::expect_identical(rotated$refresh_token, auth$refresh_token)
  testthat::expect_identical(rotated$email, "person@example.com")
})

testthat::test_that("scope checks require ChatGPT plan usage", {
  testthat::expect_true(codex_scope_granted("openid chatgpt.tokens.use.direct"))
  testthat::expect_true(codex_scope_granted("chatgpt.tokens.use.direct+email"))
  testthat::expect_false(codex_scope_granted("openid profile email offline_access"))
  testthat::expect_false(codex_scope_granted(NULL))
})

testthat::test_that("token response validation uses sanitized package conditions", {
  response <- httr2::response_json(
    status_code = 200L,
    body = list(access_token = "fixture-access", refresh_token = "fixture-refresh")
  )
  testthat::expect_identical(
    codex_token_response(response, "token exchange")$access_token,
    "fixture-access"
  )
  malformed <- testthat::expect_error(
    codex_token_response(httr2::response_json(200L, body = list(refresh_token = "x")), "refresh"),
    class = "codex_refresh_error"
  )
  testthat::expect_false(grepl("fixture-access", conditionMessage(malformed), fixed = TRUE))

  rejected <- testthat::expect_error(
    codex_token_response(
      httr2::response_json(400L, body = list(error = "invalid_grant", refresh_token = "fixture-secret")),
      "refresh"
    ),
    class = "codex_refresh_error"
  )
  testthat::expect_identical(rejected$oauth_error, "invalid_grant")
  testthat::expect_false(grepl("fixture-secret", conditionMessage(rejected), fixed = TRUE))
})

testthat::test_that("authorization URLs follow the documented registration parameters", {
  url <- codex_authorization_request_url(
    client_id = "dynamic_agent_client",
    host_id = "urn:uuid:00000000-0000-4000-8000-000000000000",
    redirect_uri = codex_redirect_uri(1455L),
    state = "fixture-state",
    nonce = "fixture-nonce",
    code_challenge = "fixture-challenge",
    id_token_hint = "fixture-id-token"
  )
  testthat::expect_true(startsWith(url, "https://auth.openai.com/api/accounts/authorize?"))
  query <- fixture_query(url)
  testthat::expect_identical(query$client_id, "dynamic_agent_client")
  testthat::expect_identical(query$agent_name_hint, "ellmercodex")
  testthat::expect_identical(query$ext_agent_host_id, "urn:uuid:00000000-0000-4000-8000-000000000000")
  testthat::expect_null(query$id_token_hint)
  testthat::expect_identical(query$response_type, "code")
  testthat::expect_identical(query$redirect_uri, "http://127.0.0.1:1455/callback")
  testthat::expect_identical(
    query$scope,
    "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
  )
  testthat::expect_identical(query$resource, "https://api.openai.com/v1")
  testthat::expect_identical(query$code_challenge_method, "S256")
  testthat::expect_identical(query$code_challenge, "fixture-challenge")
  testthat::expect_identical(query$nonce, "fixture-nonce")
  testthat::expect_null(query$originator)
  testthat::expect_null(query$codex_cli_simplified_flow)

  reauth <- fixture_query(codex_authorization_request_url(
    client_id = "oaiapp_fixtureclient",
    host_id = "urn:uuid:00000000-0000-4000-8000-000000000000",
    redirect_uri = codex_redirect_uri(1455L),
    state = "fixture-state",
    nonce = "fixture-nonce",
    code_challenge = "fixture-challenge",
    id_token_hint = "fixture-id-token"
  ))
  testthat::expect_identical(reauth$client_id, "oaiapp_fixtureclient")
  testthat::expect_identical(reauth$id_token_hint, "fixture-id-token")
  testthat::expect_null(reauth$agent_name_hint)
  testthat::expect_identical(reauth$ext_agent_host_id, "urn:uuid:00000000-0000-4000-8000-000000000000")
})

testthat::test_that("PKCE challenges are base64url SHA-256 digests without padding", {
  pkce <- codex_pkce()
  expected <- codex_base64url_encode(openssl::sha256(charToRaw(pkce$verifier)))
  testthat::expect_identical(pkce$challenge, expected)
  testthat::expect_false(grepl("[=+/]", pkce$challenge))
})

testthat::test_that("the redirect URI uses the loopback literal and callback path", {
  testthat::expect_identical(codex_redirect_uri(), "http://127.0.0.1:1455/callback")
  old <- Sys.getenv("ELLMERCODEX_CALLBACK_PORT", unset = NA_character_)
  on.exit(if (is.na(old)) Sys.unsetenv("ELLMERCODEX_CALLBACK_PORT") else Sys.setenv(ELLMERCODEX_CALLBACK_PORT = old))
  Sys.setenv(ELLMERCODEX_CALLBACK_PORT = "8123")
  testthat::expect_identical(codex_redirect_uri(), "http://127.0.0.1:8123/callback")
  Sys.setenv(ELLMERCODEX_CALLBACK_PORT = "not-a-port")
  testthat::expect_identical(codex_redirect_uri(), "http://127.0.0.1:1455/callback")
})

testthat::test_that("ID tokens are verified against JWKS, issuer, audience, and nonce", {
  testthat::skip_on_cran()
  signing <- fixture_signing_key()
  local_fixture_jwks(signing)

  claims <- codex_validate_id_token(
    fixture_id_token(signing),
    client_id = "oaiapp_fixtureclient",
    nonce = "fixture-nonce"
  )
  testthat::expect_identical(claims$sub, "fixture-subject")

  testthat::expect_error(
    codex_validate_id_token(fixture_id_token(signing), "oaiapp_fixtureclient", nonce = "other"),
    "nonce",
    class = "codex_token_exchange_error"
  )
  testthat::expect_error(
    codex_validate_id_token(fixture_id_token(signing), "oaiapp_otherclient", nonce = "fixture-nonce"),
    "audience",
    class = "codex_token_exchange_error"
  )
  testthat::expect_error(
    codex_validate_id_token(
      fixture_id_token(signing, iss = "https://example.invalid"),
      "oaiapp_fixtureclient", nonce = "fixture-nonce"
    ),
    "issuer",
    class = "codex_token_exchange_error"
  )
  testthat::expect_error(
    codex_validate_id_token(
      fixture_id_token(signing, exp = as.numeric(Sys.time()) - 3600),
      "oaiapp_fixtureclient", nonce = "fixture-nonce"
    ),
    class = "codex_token_exchange_error"
  )
  forged <- fixture_id_token(fixture_signing_key())
  testthat::expect_error(
    codex_validate_id_token(forged, "oaiapp_fixtureclient", nonce = "fixture-nonce"),
    "signature",
    class = "codex_token_exchange_error"
  )
})

testthat::test_that("first sign-in exchanges the code with the issued client ID", {
  local_codex_home()
  seen <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    codex_oauth_browse = function(url) seen$url <- url,
    codex_oauth_listen = function(redirect_uri, timeout = 300) {
      seen$redirect_uri <- redirect_uri
      list(
        code = "fixture-code",
        state = fixture_query(seen$url)$state,
        scope = "chatgpt.tokens.use.direct email offline_access openid profile resource.invoke",
        client_id = "oaiapp_fixtureclient"
      )
    },
    codex_validate_id_token = function(id_token, client_id, nonce = NULL) {
      seen$nonce <- nonce
      seen$validated_client <- client_id
      list(iss = "https://auth.openai.com", sub = "fixture-subject")
    },
    .package = "ellmercodex"
  )
  result <- httr2::with_mocked_responses(
    function(req) {
      seen$token_request <- req
      httr2::response_json(body = fixture_token_response())
    },
    codex_oauth_flow(registration = NULL, timeout = 5)
  )

  query <- fixture_query(seen$url)
  testthat::expect_identical(query$client_id, "dynamic_agent_client")
  testthat::expect_identical(query$ext_agent_host_id, codex_host_id(create = FALSE))
  testthat::expect_identical(seen$nonce, query$nonce)
  testthat::expect_identical(result$client_id, "oaiapp_fixtureclient")
  testthat::expect_identical(seen$validated_client, "oaiapp_fixtureclient")

  request <- seen$token_request
  testthat::expect_identical(request$url, "https://auth.openai.com/api/accounts/oauth/token")
  form <- request$body$data
  testthat::expect_identical(fixture_form(form$grant_type), "authorization_code")
  testthat::expect_identical(fixture_form(form$client_id), "oaiapp_fixtureclient")
  testthat::expect_identical(fixture_form(form$code), "fixture-code")
  testthat::expect_identical(fixture_form(form$redirect_uri), seen$redirect_uri)
  testthat::expect_identical(fixture_form(form$resource), "https://api.openai.com/v1")
  challenge <- codex_base64url_encode(openssl::sha256(charToRaw(fixture_form(form$code_verifier))))
  testthat::expect_identical(challenge, query$code_challenge)
  testthat::expect_null(form$client_secret)
})

testthat::test_that("sign-in rejects mismatched state and missing issued client IDs", {
  local_codex_home()
  seen <- new.env(parent = emptyenv())
  callback <- list(code = "fixture-code", state = "wrong-state", client_id = "oaiapp_fixtureclient")
  testthat::local_mocked_bindings(
    codex_oauth_browse = function(url) seen$url <- url,
    codex_oauth_listen = function(redirect_uri, timeout = 300) callback,
    .package = "ellmercodex"
  )
  testthat::expect_error(codex_oauth_flow(timeout = 5), "state", class = "codex_oauth_callback_error")

  testthat::local_mocked_bindings(
    codex_oauth_listen = function(redirect_uri, timeout = 300) {
      list(code = "fixture-code", state = fixture_query(seen$url)$state)
    },
    .package = "ellmercodex"
  )
  testthat::expect_error(codex_oauth_flow(timeout = 5), "client ID", class = "codex_oauth_callback_error")

  testthat::local_mocked_bindings(
    codex_oauth_listen = function(redirect_uri, timeout = 300) {
      list(error = "access_denied", state = fixture_query(seen$url)$state)
    },
    .package = "ellmercodex"
  )
  testthat::expect_error(codex_oauth_flow(timeout = 5), "declined", class = "codex_oauth_callback_error")
})

testthat::test_that("the loopback listener honours its timeout", {
  testthat::skip_on_cran()
  port <- httpuv::randomPort()
  testthat::expect_error(
    codex_oauth_listen(codex_redirect_uri(port), timeout = 0.2),
    class = "codex_oauth_timeout"
  )
})

testthat::test_that("persistent login stores the registration and later reauthorizes it", {
  home <- local_codex_home()
  registrations <- list()
  testthat::local_mocked_bindings(
    codex_oauth_flow = function(registration = NULL, timeout = 300) {
      registrations[[length(registrations) + 1L]] <<- list(registration)
      list(
        client_id = "oaiapp_fixtureclient",
        tokens = fixture_token_response(),
        claims = list(iss = "https://auth.openai.com", sub = "fixture-subject")
      )
    },
    .package = "ellmercodex"
  )

  auth <- ellmercodex::codex_login(persist = TRUE)
  testthat::expect_null(registrations[[1L]][[1L]])
  path <- file.path(home, "credentials.json")
  testthat::expect_true(file.exists(path))
  if (.Platform$OS.type == "unix") {
    testthat::expect_identical(format(file.info(path)$mode), "600")
  }
  stored <- jsonlite::fromJSON(path)
  testthat::expect_identical(stored$client_id, "oaiapp_fixtureclient")
  testthat::expect_identical(stored$refresh_token, "fixture-refresh-token")
  testthat::expect_identical(codex_auth(), auth)

  codex_session_clear()
  ellmercodex::codex_login(persist = TRUE)
  testthat::expect_identical(registrations[[2L]][[1L]]$client_id, "oaiapp_fixtureclient")
  testthat::expect_identical(registrations[[2L]][[1L]]$id_token, "fixture-id-token")
})

testthat::test_that("login without ChatGPT plan scope keeps only the registration", {
  home <- local_codex_home()
  testthat::local_mocked_bindings(
    codex_oauth_flow = function(registration = NULL, timeout = 300) list(
      client_id = "oaiapp_fixtureclient",
      tokens = fixture_token_response(scope = "openid profile email offline_access"),
      claims = list(sub = "fixture-subject")
    ),
    .package = "ellmercodex"
  )
  testthat::expect_error(ellmercodex::codex_login(), class = "codex_plan_scope_error")
  stored <- jsonlite::fromJSON(file.path(home, "credentials.json"))
  testthat::expect_identical(stored$client_id, "oaiapp_fixtureclient")
  testthat::expect_null(stored$access_token)
  testthat::expect_null(stored$refresh_token)
  testthat::expect_null(codex_session_get())
  testthat::expect_null(codex_credentials_load(required = FALSE))
})

testthat::test_that("non-persistent login remains usable in the current process", {
  home <- local_codex_home()
  testthat::local_mocked_bindings(
    codex_oauth_flow = function(registration = NULL, timeout = 300) list(
      client_id = "oaiapp_fixtureclient",
      tokens = fixture_token_response(),
      claims = list(sub = "fixture-subject")
    ),
    .package = "ellmercodex"
  )

  logged_in <- ellmercodex::codex_login(persist = FALSE)
  testthat::expect_identical(codex_auth(), logged_in)
  testthat::expect_false(codex_session_persists())
  testthat::expect_true(ellmercodex::codex_account()$authenticated)
  testthat::expect_false(file.exists(file.path(home, "credentials.json")))
})

testthat::test_that("persisted refresh rotates tokens with the issued client ID", {
  home <- local_codex_home()
  auth <- fake_codex_auth()
  auth$expires_at <- as.numeric(Sys.time()) - 10
  codex_store_write(auth)
  seen <- new.env(parent = emptyenv())
  seen$calls <- 0L

  refreshed <- httr2::with_mocked_responses(
    function(req) {
      seen$calls <- seen$calls + 1L
      seen$request <- req
      httr2::response_json(body = fixture_token_response(
        access_token = "fixture-rotated-access",
        refresh_token = "fixture-rotated-refresh",
        id_token = NULL
      ))
    },
    codex_refresh(auth, persist = TRUE)
  )
  testthat::expect_identical(seen$calls, 1L)
  form <- seen$request$body$data
  testthat::expect_identical(fixture_form(form$grant_type), "refresh_token")
  testthat::expect_identical(fixture_form(form$client_id), "oaiapp_fixtureclient")
  testthat::expect_identical(fixture_form(form$refresh_token), "fixture-refresh-token")
  testthat::expect_identical(fixture_form(form$resource), "https://api.openai.com/v1")
  testthat::expect_identical(refreshed$refresh_token, "fixture-rotated-refresh")
  testthat::expect_identical(codex_store_read()$refresh_token, "fixture-rotated-refresh")
  testthat::expect_false(dir.exists(file.path(home, "refresh.lock")))
})

testthat::test_that("refresh reuses a token another process already rotated", {
  local_codex_home()
  stale <- fake_codex_auth()
  stale$expires_at <- as.numeric(Sys.time()) - 10
  fresh <- fake_codex_auth()
  fresh$access_token <- "fixture-other-process-access"
  fresh$refresh_token <- "fixture-other-process-refresh"
  codex_store_write(fresh)

  refreshed <- httr2::with_mocked_responses(
    function(req) stop("no network expected"),
    codex_refresh(stale, persist = TRUE)
  )
  testthat::expect_identical(refreshed$access_token, "fixture-other-process-access")
})

testthat::test_that("an invalid refresh token clears tokens but keeps the registration", {
  local_codex_home()
  auth <- fake_codex_auth()
  auth$expires_at <- as.numeric(Sys.time()) - 10
  auth$id_token <- "fixture-id-token"
  codex_store_write(auth)

  error <- testthat::expect_error(
    httr2::with_mocked_responses(
      function(req) httr2::response_json(400L, body = list(error = "refresh_token_reused")),
      codex_refresh(auth, persist = TRUE)
    ),
    class = "codex_refresh_error"
  )
  testthat::expect_identical(error$oauth_error, "refresh_token_reused")
  stored <- codex_store_read()
  testthat::expect_identical(stored$client_id, "oaiapp_fixtureclient")
  testthat::expect_identical(stored$id_token, "fixture-id-token")
  testthat::expect_null(stored$refresh_token)
})

testthat::test_that("a temporary refresh failure preserves stored credentials", {
  local_codex_home()
  auth <- fake_codex_auth()
  auth$expires_at <- as.numeric(Sys.time()) - 10
  codex_store_write(auth)
  testthat::expect_error(
    httr2::with_mocked_responses(
      function(req) httr2::response_json(503L, body = list(error = "temporarily_unavailable")),
      codex_refresh(auth, persist = TRUE)
    ),
    class = "codex_refresh_error"
  )
  testthat::expect_identical(codex_store_read()$refresh_token, "fixture-refresh-token")
})

testthat::test_that("process-only refresh never writes the credential file", {
  home <- local_codex_home()
  auth <- fake_codex_auth()
  refreshed <- httr2::with_mocked_responses(
    function(req) httr2::response_json(body = fixture_token_response(
      access_token = "fixture-memory-access", id_token = NULL
    )),
    codex_refresh(auth, persist = FALSE)
  )
  testthat::expect_identical(refreshed$access_token, "fixture-memory-access")
  testthat::expect_false(file.exists(file.path(home, "credentials.json")))
})

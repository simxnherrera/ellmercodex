testthat::test_that("PKCE and OAuth state are generated and validated offline", {
  pkce <- codex_pkce()
  testthat::expect_match(pkce$verifier, "^[A-Za-z0-9_-]{43,128}$")
  testthat::expect_identical(
    pkce$challenge,
    codex_base64url_encode(openssl::sha256(charToRaw(pkce$verifier)))
  )

  state <- codex_oauth_state()
  testthat::expect_true(codex_validate_state(state, state))
  testthat::expect_false(codex_validate_state(state, paste0(state, "x")))
  testthat::expect_false(codex_validate_state(state, NA_character_))
})

testthat::test_that("callback parsing normalizes httpuv's leading question mark", {
  query <- codex_parse_query("?code=fixture-code&state=fixture-state&scope=openid+profile")
  testthat::expect_identical(query$code, "fixture-code")
  testthat::expect_identical(query$scope, "openid profile")

  success <- codex_callback_result(query, "fixture-state")
  testthat::expect_identical(success$code, "fixture-code")
  testthat::expect_null(success$error)

  mismatch <- codex_callback_result(query, "wrong-state")
  testthat::expect_null(mismatch$code)
  testthat::expect_match(mismatch$error, "state")

  denied <- codex_callback_result(
    codex_parse_query("error=access_denied&state=fixture-state"),
    "fixture-state"
  )
  testthat::expect_match(denied$error, "access_denied")
  testthat::expect_false(grepl("fixture", denied$error, fixed = TRUE))
})

testthat::test_that("JWT claims and expiry use the access-token metadata safely", {
  claims <- codex_base64url_encode(charToRaw(
    '{"exp":2000,"https://api.openai.com/auth":{"chatgpt_account_id":"fixture-account"}}'
  ))
  access_token <- paste("header", claims, "signature", sep = ".")
  tokens <- list(
    access_token = access_token,
    refresh_token = "fixture-refresh",
    expires_in = 3600
  )
  auth <- codex_auth_from_tokens(tokens)

  testthat::expect_identical(auth$account_id, "fixture-account")
  testthat::expect_false(codex_token_expired(auth, skew = 0, now = 1999))
  testthat::expect_true(codex_token_expired(auth, skew = 0, now = 2000))
  testthat::expect_identical(codex_token_expires_at(auth), 2000)
  testthat::expect_error(
    codex_auth_from_tokens(list(access_token = "not-a-jwt", refresh_token = "x")),
    class = "codex_account_error"
  )
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
})

testthat::test_that("non-persistent login remains usable in the current process", {
  codex_session_clear()
  on.exit(codex_session_clear(), add = TRUE)
  auth <- fake_codex_auth()

  testthat::local_mocked_bindings(
    codex_pkce = function() list(verifier = "fixture-verifier", challenge = "fixture-challenge"),
    codex_oauth_state = function() "fixture-state",
    codex_authorize_url = function(pkce, state) "https://example.invalid/authorize",
    codex_wait_for_callback = function(expected_state, timeout, on_ready) "fixture-code",
    codex_exchange_code = function(code, verifier) list(access_token = "unused"),
    codex_auth_from_tokens = function(tokens, previous = NULL) auth,
    codex_credentials_load = function(required = TRUE) {
      testthat::fail("A non-persistent session must not read credential storage.")
    },
    .package = "ellmercodex"
  )

  logged_in <- ellmercodex::codex_login(persist = FALSE)
  testthat::expect_identical(logged_in, auth)
  testthat::expect_identical(codex_auth(), auth)
  testthat::expect_false(codex_session_persists())
  testthat::expect_true(ellmercodex::codex_account()$authenticated)
})

testthat::test_that("refresh rotation is persisted once without a generation retry", {
  claims <- codex_base64url_encode(charToRaw(jsonlite::toJSON(
    list(
      exp = as.numeric(Sys.time()) + 3600,
      `https://api.openai.com/auth` = list(chatgpt_account_id = "fixture-account-id")
    ),
    auto_unbox = TRUE
  )))
  access_token <- paste("header", claims, "signature", sep = ".")
  stored <- new.env(parent = emptyenv())
  stored$calls <- 0L
  testthat::local_mocked_bindings(
    codex_credentials_store = function(auth) {
      stored$calls <- stored$calls + 1L
      stored$auth <- auth
      invisible(auth)
    },
    .package = "ellmercodex"
  )

  refreshed <- httr2::with_mocked_responses(
    function(req) {
      httr2::response_json(
        status_code = 200L,
        body = list(
          access_token = access_token,
          refresh_token = "fixture-rotated-refresh",
          expires_in = 3600
        )
      )
    },
    codex_refresh(fake_codex_auth(), persist = TRUE)
  )

  testthat::expect_identical(refreshed$refresh_token, "fixture-rotated-refresh")
  testthat::expect_identical(stored$calls, 1L)
  testthat::expect_identical(stored$auth, refreshed)
})

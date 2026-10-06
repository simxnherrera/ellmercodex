# OAuth primitives and the public authentication lifecycle for the documented
# "Sign in with ChatGPT" dynamic-registration flow.

`%||%` <- function(x, y) if (is.null(x)) y else x

.codex_session <- new.env(parent = emptyenv())
.codex_session$auth <- NULL
.codex_session$persist <- FALSE
.codex_session$oidc <- NULL
.codex_session$jwks <- NULL

codex_session_set <- function(auth, persist = FALSE) {
  if (!inherits(auth, "codex_auth")) {
    codex_auth_abort("The Codex session credential was malformed.", "codex_auth_argument_error")
  }
  .codex_session$auth <- auth
  .codex_session$persist <- isTRUE(persist)
  invisible(auth)
}

codex_session_get <- function() {
  auth <- .codex_session$auth
  if (inherits(auth, "codex_auth")) auth else NULL
}

codex_session_persists <- function() {
  isTRUE(.codex_session$persist)
}

codex_session_clear <- function() {
  .codex_session$auth <- NULL
  .codex_session$persist <- FALSE
  invisible(TRUE)
}

codex_base64url_decode <- function(value) {
  codex_auth_require_string(value, "value")
  if (!grepl("^[A-Za-z0-9_-]+$", value)) {
    codex_auth_abort("The encoded OAuth value was malformed.", "codex_oauth_argument_error")
  }
  value <- chartr("-_", "+/", value)
  padding <- (4L - (nchar(value) %% 4L)) %% 4L
  if (padding > 0L) value <- paste0(value, strrep("=", padding))
  tryCatch(openssl::base64_decode(value), error = function(error) {
    codex_auth_abort("The encoded OAuth value was malformed.", "codex_oauth_argument_error")
  })
}

codex_base64url_encode <- function(value) {
  encoded <- openssl::base64_encode(value)
  sub("=+$", "", chartr("+/", "-_", encoded))
}

codex_random_token <- function(bytes = 32L) {
  codex_base64url_encode(openssl::rand_bytes(bytes))
}

codex_pkce <- function() {
  verifier <- codex_random_token(32L)
  list(
    verifier = verifier,
    challenge = codex_base64url_encode(openssl::sha256(charToRaw(verifier)))
  )
}

codex_jwt_part <- function(token, index) {
  if (!codex_auth_scalar_character(token)) {
    return(NULL)
  }
  parts <- strsplit(token, ".", fixed = TRUE)[[1L]]
  if (length(parts) != 3L || !nzchar(parts[[index]])) {
    return(NULL)
  }
  tryCatch(
    jsonlite::fromJSON(rawToChar(codex_base64url_decode(parts[[index]])), simplifyVector = TRUE),
    error = function(error) NULL
  )
}

codex_jwt_claims <- function(token) {
  codex_jwt_part(token, 2L)
}

codex_scope_values <- function(scope) {
  if (!is.character(scope) || length(scope) == 0L) {
    return(character())
  }
  values <- unlist(strsplit(paste(scope[!is.na(scope)], collapse = " "), "[[:space:]+]+"))
  values[nzchar(values)]
}

codex_scope_granted <- function(scope, required = codex_plan_scope()) {
  all(required %in% codex_scope_values(scope))
}

# OAuth error codes from the token endpoint that mean the refresh token can no
# longer be used. The saved registration is kept for reauthorization.
codex_refresh_reauth_codes <- function() {
  c(
    "invalid_grant", "invalid_refresh_token", "token_expired",
    "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"
  )
}

codex_oauth_error_code <- function(value) {
  if (!is.list(value)) {
    return(NULL)
  }
  error <- value$error
  code <- if (is.list(error)) error$code %||% error$type else error
  if (codex_auth_scalar_character(code)) code else NULL
}

codex_token_response <- function(response, operation = "token exchange") {
  status <- tryCatch(httr2::resp_status(response), error = function(error) NA_integer_)
  class <- if (identical(operation, "refresh")) "codex_refresh_error" else "codex_token_exchange_error"
  value <- tryCatch(
    httr2::resp_body_json(response, simplifyVector = TRUE),
    error = function(error) NULL
  )
  if (!is.finite(status) || status < 200L || status >= 300L) {
    code <- codex_oauth_error_code(value)
    rlang::abort(
      sprintf(
        "Codex OAuth %s failed (HTTP %s%s). Please authenticate again with codex_login().",
        operation,
        if (is.finite(status)) status else "unknown",
        if (is.null(code)) "" else paste0(", ", codex_redact(code))
      ),
      class = unique(c(class, "codex_auth_error")),
      oauth_error = code,
      status = status
    )
  }

  valid_access_token <- is.list(value) && codex_auth_scalar_character(value$access_token)
  if (!valid_access_token) {
    codex_auth_abort(
      sprintf("Codex OAuth %s returned a malformed credential response.", operation),
      class
    )
  }
  value
}

codex_token_request <- function(fields, operation = "token exchange") {
  request <- httr2::request(codex_token_url()) |>
    httr2::req_body_form(!!!fields) |>
    httr2::req_user_agent(codex_user_agent()) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) {
    codex_auth_abort(
      sprintf(
        "Codex OAuth %s failed because of a network error; retry, or run codex_login() if it persists.",
        operation
      ),
      if (identical(operation, "refresh")) "codex_refresh_error" else "codex_token_exchange_error"
    )
  })
  codex_token_response(response, operation)
}

codex_oidc_cached <- function() {
  if (is.null(.codex_session$oidc)) {
    .codex_session$oidc <- codex_oidc_configuration()
  }
  .codex_session$oidc
}

codex_jwks <- function(refresh = FALSE) {
  if (!isTRUE(refresh) && is.list(.codex_session$jwks)) {
    return(.codex_session$jwks)
  }
  uri <- codex_oidc_cached()$jwks_uri
  if (!codex_auth_scalar_character(uri) || !grepl("^https://", uri)) {
    return(NULL)
  }
  request <- httr2::request(uri) |>
    httr2::req_user_agent(codex_user_agent()) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) NULL)
  if (is.null(response) || httr2::resp_status(response) != 200L) {
    return(NULL)
  }
  value <- tryCatch(httr2::resp_body_json(response, simplifyVector = FALSE), error = function(error) NULL)
  keys <- if (is.list(value)) value$keys else NULL
  if (!is.list(keys)) {
    return(NULL)
  }
  .codex_session$jwks <- keys
  keys
}

codex_jwk_for <- function(header, keys) {
  if (!is.list(keys) || length(keys) == 0L) {
    return(NULL)
  }
  kid <- if (is.list(header)) header$kid else NULL
  if (codex_auth_scalar_character(kid)) {
    for (key in keys) {
      if (is.list(key) && identical(key$kid, kid)) return(key)
    }
    return(NULL)
  }
  if (length(keys) == 1L) keys[[1L]] else NULL
}

# Verify an ID token as the documentation requires: signature against
# OpenAI's published JWKS, issuer, audience (the issued client ID),
# expiration, and the per-attempt nonce.
codex_validate_id_token <- function(id_token, client_id, nonce = NULL) {
  fail <- function(reason) {
    codex_auth_abort(
      paste0("The ChatGPT ID token could not be verified: ", reason, "."),
      "codex_token_exchange_error"
    )
  }
  header <- codex_jwt_part(id_token, 1L)
  if (!is.list(header)) fail("it was malformed")
  key <- codex_jwk_for(header, codex_jwks())
  if (is.null(key)) key <- codex_jwk_for(header, codex_jwks(refresh = TRUE))
  if (is.null(key)) fail("no matching signing key was published")
  claims <- tryCatch(
    {
      pubkey <- jose::read_jwk(jsonlite::toJSON(key, auto_unbox = TRUE))
      unclass(jose::jwt_decode_sig(id_token, pubkey))
    },
    error = function(error) NULL
  )
  if (!is.list(claims)) fail("the signature or validity period was rejected")
  issuer <- codex_oidc_cached()$issuer %||% codex_oauth_issuer()
  if (!identical(claims$iss, issuer)) fail("the issuer did not match")
  if (!is.character(claims$aud) || !client_id %in% claims$aud) fail("the audience did not match")
  if (!is.numeric(claims$exp)) fail("it had no expiration")
  if (!is.null(nonce) && !identical(claims$nonce, nonce)) fail("the nonce did not match")
  if (!codex_auth_scalar_character(claims$sub)) fail("it had no subject")
  claims
}

codex_authorization_request_url <- function(
  client_id,
  host_id,
  redirect_uri,
  state,
  nonce,
  code_challenge,
  id_token_hint = NULL
) {
  new_registration <- identical(client_id, codex_dynamic_client_id())
  query <- list(
    client_id = client_id,
    agent_name_hint = if (new_registration) codex_agent_name(),
    ext_agent_host_id = host_id,
    id_token_hint = if (!new_registration) id_token_hint,
    response_type = "code",
    redirect_uri = redirect_uri,
    scope = codex_oauth_scope(),
    resource = codex_oauth_resource(),
    state = state,
    nonce = nonce,
    code_challenge_method = "S256",
    code_challenge = code_challenge
  )
  query <- Filter(Negate(is.null), query)
  httr2::url_modify(codex_authorization_url(), query = query)
}

codex_callback_page <- function(ok) {
  paste0(
    "<!doctype html><html><head><meta charset=\"utf-8\"><title>ellmercodex</title></head>",
    "<body><p>",
    if (ok) "Sign-in complete. You can close this page and return to R."
    else "Sign-in did not complete. Return to R for details.",
    "</p></body></html>"
  )
}

# A minimal loopback listener with an explicit timeout. It accepts exactly one
# request on the documented `/callback` path and returns its query values.
codex_oauth_listen <- function(redirect_uri, timeout = 300) {
  parsed <- httr2::url_parse(redirect_uri)
  port <- as.integer(parsed$port)
  path <- parsed$path %||% "/callback"
  state <- new.env(parent = emptyenv())
  state$query <- NULL
  app <- list(call = function(request) {
    if (!identical(request$PATH_INFO, path)) {
      return(list(status = 404L, headers = list(`Content-Type` = "text/plain"), body = "Not found"))
    }
    query <- request$QUERY_STRING
    state$query <- if (is.character(query) && nzchar(query)) {
      httr2::url_parse(paste0("http://127.0.0.1/?", sub("^\\?", "", query)))$query
    } else {
      list()
    }
    ok <- is.list(state$query) && !is.null(state$query$code) && is.null(state$query$error)
    list(
      status = 200L,
      headers = list(`Content-Type` = "text/html; charset=utf-8"),
      body = codex_callback_page(ok)
    )
  })
  server <- tryCatch(httpuv::startServer("127.0.0.1", port, app), error = function(error) NULL)
  if (is.null(server)) {
    codex_auth_abort(
      sprintf(
        "The OAuth callback port %d is unavailable. Close the program using it or set ELLMERCODEX_CALLBACK_PORT.",
        port
      ),
      "codex_oauth_callback_error"
    )
  }
  on.exit(httpuv::stopServer(server), add = TRUE)
  deadline <- as.numeric(Sys.time()) + timeout
  while (is.null(state$query)) {
    if (as.numeric(Sys.time()) > deadline) {
      codex_auth_abort("Timed out waiting for the OAuth browser callback.", "codex_oauth_timeout")
    }
    httpuv::service(100)
  }
  httpuv::service(10)
  state$query
}

codex_oauth_browse <- function(url) {
  # The authorization URL can carry an ID token hint; it is never printed or
  # logged by this package. Configure `options(browser = )` on headless hosts.
  utils::browseURL(url)
}

# Run one authorization attempt and return the issued client ID, the token
# response, and the verified ID token claims. `registration` is a previous
# record whose issued client ID should be reauthorized, or NULL for a new
# registration.
codex_oauth_flow <- function(registration = NULL, timeout = 300) {
  if (!requireNamespace("httpuv", quietly = TRUE)) {
    codex_auth_abort(
      "The browser OAuth flow requires the `httpuv` package.",
      "codex_oauth_callback_error"
    )
  }
  host_id <- codex_host_id(create = TRUE)
  reauthorize <- is.list(registration) && codex_auth_scalar_character(registration$client_id)
  client_id <- if (reauthorize) registration$client_id else codex_dynamic_client_id()
  redirect_uri <- codex_redirect_uri()
  state <- codex_random_token()
  nonce <- codex_random_token()
  pkce <- codex_pkce()
  url <- codex_authorization_request_url(
    client_id = client_id,
    host_id = host_id,
    redirect_uri = redirect_uri,
    state = state,
    nonce = nonce,
    code_challenge = pkce$challenge,
    id_token_hint = if (reauthorize) registration$id_token
  )
  codex_oauth_browse(url)
  query <- codex_oauth_listen(redirect_uri, timeout = timeout)

  if (!is.null(query$error)) {
    detail <- codex_redact(as.character(query$error))
    codex_auth_abort(
      paste0(
        "ChatGPT sign-in was not completed (", detail, ").",
        if (identical(query$error, "access_denied")) " Consent was declined." else ""
      ),
      "codex_oauth_callback_error"
    )
  }
  if (!identical(query$state, state)) {
    codex_auth_abort("The OAuth callback state did not match.", "codex_oauth_callback_error")
  }
  if (!codex_auth_scalar_character(query$code)) {
    codex_auth_abort("The OAuth callback did not include an authorization code.", "codex_oauth_callback_error")
  }
  if (!reauthorize) {
    client_id <- query$client_id
    if (!codex_auth_scalar_character(client_id) || !grepl("^[A-Za-z0-9_.-]+$", client_id)) {
      codex_auth_abort(
        "The OAuth callback did not include the issued client ID.",
        "codex_oauth_callback_error"
      )
    }
  }

  tokens <- codex_token_request(
    list(
      grant_type = "authorization_code",
      client_id = client_id,
      code = query$code,
      code_verifier = pkce$verifier,
      redirect_uri = redirect_uri,
      resource = codex_oauth_resource()
    ),
    "token exchange"
  )
  if (is.null(tokens$scope) && !is.null(query$scope)) tokens$scope <- query$scope
  claims <- codex_validate_id_token(tokens$id_token, client_id = client_id, nonce = nonce)
  list(client_id = client_id, tokens = tokens, claims = claims)
}

codex_auth_from_tokens <- function(tokens, client_id = NULL, claims = NULL, previous = NULL) {
  if (!is.list(tokens) || !codex_auth_scalar_character(tokens$access_token)) {
    codex_auth_abort(
      "The OAuth token response did not contain an access token.",
      "codex_token_exchange_error"
    )
  }
  client_id <- client_id %||% previous$client_id
  if (!codex_auth_scalar_character(client_id)) {
    codex_auth_abort(
      "The OAuth credential is missing its issued client ID.",
      "codex_token_exchange_error"
    )
  }
  refresh_token <- tokens$refresh_token %||% previous$refresh_token
  if (!codex_auth_scalar_character(refresh_token)) {
    codex_auth_abort(
      "The OAuth credential response did not contain a refresh token.",
      "codex_token_exchange_error"
    )
  }

  expires_in <- suppressWarnings(as.numeric(tokens$expires_in %||% NA_real_))
  if (length(expires_in) != 1L || !is.finite(expires_in) || expires_in < 0) {
    expires_in <- NA_real_
  }
  expires_at <- if (is.finite(expires_in)) as.numeric(Sys.time()) + expires_in else NA_real_
  claim <- function(name) {
    value <- if (is.list(claims)) claims[[name]] else NULL
    if (codex_auth_scalar_character(value)) value else previous[[name]]
  }

  structure(
    list(
      client_id = client_id,
      issuer = claim("iss") %||% previous$issuer,
      sub = claim("sub"),
      email = claim("email"),
      id_token = tokens$id_token %||% previous$id_token,
      access_token = tokens$access_token,
      refresh_token = refresh_token,
      token_type = tokens$token_type %||% "Bearer",
      expires_at = expires_at,
      earliest_refresh_at = tokens$earliest_refresh_at,
      scope = tokens$scope %||% previous$scope
    ),
    class = c("codex_auth", "list")
  )
}

codex_token_expires_at <- function(auth) {
  if (!is.list(auth)) {
    return(NA_real_)
  }
  value <- suppressWarnings(as.numeric(auth$expires_at %||% NA_real_))
  if (length(value) == 1L && is.finite(value)) {
    return(value)
  }
  claims <- codex_jwt_claims(auth$access_token)
  jwt_exp <- if (is.list(claims)) suppressWarnings(as.numeric(claims$exp %||% NA_real_)) else NA_real_
  if (length(jwt_exp) == 1L && is.finite(jwt_exp)) jwt_exp else NA_real_
}

codex_token_expired <- function(auth, skew = 60, now = as.numeric(Sys.time())) {
  expires_at <- codex_token_expires_at(auth)
  !is.finite(expires_at) || expires_at <= (now + skew)
}

codex_refresh_exchange <- function(auth) {
  tokens <- tryCatch(
    codex_token_request(
      list(
        grant_type = "refresh_token",
        client_id = auth$client_id,
        refresh_token = auth$refresh_token,
        resource = codex_oauth_resource()
      ),
      "refresh"
    ),
    codex_refresh_error = function(error) error
  )
  if (inherits(tokens, "codex_refresh_error")) {
    return(tokens)
  }
  # A refreshed ID token is only retained for future `id_token_hint` use.
  if (codex_auth_scalar_character(tokens$id_token)) {
    valid <- tryCatch(
      {
        codex_validate_id_token(tokens$id_token, client_id = auth$client_id)
        TRUE
      },
      error = function(error) FALSE
    )
    if (!valid) tokens$id_token <- NULL
  }
  codex_auth_from_tokens(tokens, previous = auth)
}

codex_refresh <- function(auth, persist = TRUE) {
  if (!inherits(auth, "codex_auth") || !codex_auth_scalar_character(auth$refresh_token) ||
      !codex_auth_scalar_character(auth$client_id)) {
    codex_auth_abort("The Codex credential cannot be refreshed.", "codex_refresh_error")
  }
  if (!isTRUE(persist)) {
    refreshed <- codex_refresh_exchange(auth)
    if (inherits(refreshed, "condition")) stop(refreshed)
    return(refreshed)
  }
  codex_with_refresh_lock({
    # Another process may already have rotated the shared refresh token.
    stored <- codex_store_read()
    if (is.list(stored) && identical(stored$client_id, auth$client_id) &&
        codex_auth_scalar_character(stored$refresh_token)) {
      if (is.null(stored$expires_at)) stored$expires_at <- NA_real_
      stored <- codex_credentials_as_auth(stored)
      if (!identical(stored$access_token, auth$access_token) && !codex_token_expired(stored)) {
        return(stored)
      }
      auth <- stored
    }
    refreshed <- codex_refresh_exchange(auth)
    if (inherits(refreshed, "condition")) {
      if (isTRUE(refreshed$oauth_error %in% codex_refresh_reauth_codes())) {
        codex_store_clear_tokens()
      }
      stop(refreshed)
    }
    codex_store_write(refreshed)
    refreshed
  })
}

codex_auth <- function(force_refresh = FALSE) {
  auth <- codex_session_get()
  persist <- codex_session_persists()
  if (is.null(auth)) {
    auth <- codex_credentials_load()
    persist <- TRUE
    codex_session_set(auth, persist = TRUE)
  }
  if (isTRUE(force_refresh) || codex_token_expired(auth)) {
    auth <- codex_refresh(auth, persist = persist)
    codex_session_set(auth, persist = persist)
  }
  auth
}

#' Sign in with ChatGPT in the browser.
#'
#' `codex_login()` is the explicit authentication entry point. It follows
#' OpenAI's documented "Sign in with ChatGPT" flow for open-source, locally
#' hosted apps: it opens the system browser for registration and consent,
#' listens once on the loopback callback, exchanges the PKCE-protected code
#' for tokens with the issued client ID, verifies the ID token, and checks that
#' ChatGPT plan usage (`chatgpt.tokens.use.direct`) was granted.
#'
#' The first sign-in creates a registration bound to the selected ChatGPT
#' account and workspace. Later sign-ins reauthorize that registration. Use
#' [codex_logout()] first to sign in with a different account or workspace.
#' The package never reads credentials created by Codex CLI or another
#' application.
#'
#' @param persist Whether to save the credential for later sessions. The
#'   default is `TRUE`; the credential is written to this package's own
#'   directory (see Details) with owner-only permissions. Use `FALSE` for a
#'   process-only session.
#' @param timeout Maximum callback wait in seconds. This must be one positive
#'   number. The loopback listener is closed when authentication succeeds,
#'   fails, or times out. When `persist = FALSE`, the credential remains
#'   available to [chat_codex()] only in the current R process.
#'
#' @details Credentials are stored in `tools::R_user_dir("ellmercodex",
#'   "config")`, or in the directory named by the `ELLMERCODEX_HOME`
#'   environment variable. The same directory holds a stable, opaque host
#'   identifier (`ext_agent_host_id`) that is created before the first
#'   sign-in, even when `persist = FALSE`, because the flow requires it to be
#'   stable for each host.
#'
#' @return An internal `codex_auth` object. Use [codex_account()] for a safe
#'   account summary; token fields are intentionally not printed.
#' @note This function is interactive: it opens the default browser and
#'   listens on `http://127.0.0.1:1455/callback` (set
#'   `ELLMERCODEX_CALLBACK_PORT` to use another port).
#' @section Conditions:
#' Invalid arguments signal `codex_auth_argument_error`; callback and token
#' failures use `codex_oauth_callback_error`, `codex_oauth_timeout`, or
#' `codex_token_exchange_error` as appropriate. If ChatGPT plan usage was not
#' granted, `codex_plan_scope_error` is signalled.
#' @examplesIf interactive()
#' auth <- codex_login()
#' codex_account(auth)
#' @export
codex_login <- function(persist = TRUE, timeout = 300) {
  if (!is.logical(persist) || length(persist) != 1L || is.na(persist)) {
    codex_auth_abort("`persist` must be one `TRUE` or `FALSE` value.", "codex_auth_argument_error")
  }
  if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) {
    codex_auth_abort("`timeout` must be one positive number of seconds.", "codex_auth_argument_error")
  }

  registration <- codex_session_get()
  if (is.null(registration)) {
    registration <- tryCatch(codex_store_read(), error = function(error) NULL)
  }
  result <- codex_oauth_flow(registration = registration, timeout = timeout)
  auth <- codex_auth_from_tokens(result$tokens, client_id = result$client_id, claims = result$claims)

  if (!codex_scope_granted(auth$scope)) {
    if (isTRUE(persist)) {
      # Keep the registration so a later sign-in reauthorizes it.
      record <- unclass(auth)
      record[c("access_token", "refresh_token", "expires_at", "earliest_refresh_at")] <- NULL
      codex_store_write(record)
    }
    codex_auth_abort(
      paste(
        "ChatGPT plan usage was not granted (missing the",
        codex_plan_scope(), "scope). Run codex_login() again and allow",
        "ChatGPT plan usage, or check that your plan and workspace are eligible."
      ),
      "codex_plan_scope_error"
    )
  }

  if (isTRUE(persist)) codex_store_write(auth)
  codex_session_set(auth, persist = persist)
  auth
}

#' Show a redacted Codex authentication summary.
#'
#' The account identifier and all token material are deliberately replaced or
#' omitted. Calling this function does not open a browser; an expired stored
#' credential may be refreshed.
#'
#' @param auth Optional in-memory credential. If omitted, the current
#'   process-local session and then the package's own credential store are
#'   checked.
#' @return A one-row data frame with columns:
#'     \item{`authenticated`}{Logical; whether a valid package credential was found.}
#'     \item{`account`}{Always `"<redacted>"`; account identifiers are never returned.}
#'     \item{`expires_at`}{The access-token expiry as a UTC `POSIXct` value, or `NA` when unauthenticated.}
#' @section Conditions:
#' A malformed in-memory credential signals `codex_auth_argument_error` and a
#' malformed stored value signals `codex_credential_store_error`.
#' @examplesIf interactive()
#' codex_account()
#' @export
codex_account <- function(auth = NULL) {
  if (is.null(auth)) auth <- codex_session_get()
  if (is.null(auth)) auth <- codex_credentials_load(required = FALSE)
  if (is.null(auth)) {
    return(data.frame(
      authenticated = FALSE,
      account = "<redacted>",
      expires_at = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"),
      stringsAsFactors = FALSE
    ))
  }
  if (!inherits(auth, "codex_auth")) {
    codex_auth_abort("`auth` must be a Codex credential.", "codex_auth_argument_error")
  }
  expiry <- codex_token_expires_at(auth)
  data.frame(
    authenticated = TRUE,
    account = "<redacted>",
    expires_at = as.POSIXct(expiry, origin = "1970-01-01", tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

#' @export
print.codex_auth <- function(x, ...) {
  print(codex_account(x), ...)
  invisible(x)
}

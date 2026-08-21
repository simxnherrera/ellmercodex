codex_base64url_encode <- function(value) {
  encoded <- openssl::base64_encode(value)
  encoded <- chartr("+/", "-_", encoded)
  sub("=+$", "", encoded)
}

codex_base64url_decode <- function(value) {
  value <- chartr("-_", "+/", value)
  padding <- (4L - (nchar(value) %% 4L)) %% 4L
  if (padding > 0L) value <- paste0(value, strrep("=", padding))
  openssl::base64_decode(value)
}

codex_pkce <- function() {
  # 64 random bytes encode to an 86-character RFC 7636 unreserved verifier.
  verifier <- codex_base64url_encode(openssl::rand_bytes(64L))
  challenge <- codex_base64url_encode(openssl::sha256(charToRaw(verifier)))
  list(verifier = verifier, challenge = challenge)
}

codex_oauth_state <- function() {
  codex_base64url_encode(openssl::rand_bytes(32L))
}

codex_validate_state <- function(expected, received) {
  is.character(expected) && length(expected) == 1L &&
    is.character(received) && length(received) == 1L &&
    nzchar(expected) && identical(expected, received)
}

codex_parse_query <- function(query) {
  if (is.null(query) || !nzchar(query)) return(list())
  # httpuv supplies QUERY_STRING with a leading "?"; CGI-style parsers often do
  # not. Normalize both shapes before splitting parameter names.
  query <- sub("^\\?", "", query)

  decode <- function(value) {
    utils::URLdecode(gsub("+", " ", value, fixed = TRUE))
  }
  pairs <- strsplit(query, "&", fixed = TRUE)[[1L]]
  out <- lapply(pairs, function(pair) {
    parts <- strsplit(pair, "=", fixed = TRUE)[[1L]]
    list(name = decode(parts[[1L]]), value = decode(paste(parts[-1L], collapse = "=")))
  })
  stats::setNames(lapply(out, `[[`, "value"), vapply(out, `[[`, "", "name"))
}

codex_authorize_url <- function(pkce, state) {
  params <- list(
    response_type = "code",
    client_id = codex_oauth_client_id(),
    redirect_uri = codex_redirect_uri(),
    scope = "openid profile email offline_access",
    code_challenge = pkce$challenge,
    code_challenge_method = "S256",
    id_token_add_organizations = "true",
    codex_cli_simplified_flow = "true",
    state = state,
    originator = codex_originator()
  )
  httr2::url_modify(codex_authorization_url(), query = params)
}

codex_callback_html <- function(success) {
  status <- if (success) "Authorization received" else "Authorization failed"
  paste0(
    "<!doctype html><html><head><meta charset='utf-8'><title>", status,
    "</title></head><body><h1>", status,
    "</h1><p>You may close this window and return to R.</p></body></html>"
  )
}

codex_callback_result <- function(query, expected_state) {
  if (!codex_validate_state(expected_state, query$state)) {
    return(list(code = NULL, error = "OAuth state validation failed."))
  }

  code <- query$code
  if (is.character(code) && length(code) == 1L && nzchar(code)) {
    return(list(code = code, error = NULL))
  }

  error_code <- query$error
  safe_error <- is.character(error_code) && length(error_code) == 1L &&
    grepl("^[A-Za-z0-9._-]{1,80}$", error_code)
  if (safe_error) {
    return(list(
      code = NULL,
      error = sprintf("Authorization failed (%s).", error_code)
    ))
  }

  # Names reveal the callback shape without exposing state, codes, descriptions,
  # or any other values returned by the authorization server.
  parameter_names <- setdiff(names(query), c("code", "state"))
  parameter_names <- parameter_names[grepl("^[A-Za-z0-9._-]{1,80}$", parameter_names)]
  suffix <- if (length(parameter_names) == 0L) {
    ""
  } else {
    sprintf(" Safe parameter names received: %s.", paste(parameter_names, collapse = ", "))
  }
  list(
    code = NULL,
    error = paste0("The OAuth callback did not contain an authorization code.", suffix)
  )
}

codex_wait_for_callback <- function(expected_state, timeout = 300, on_ready = NULL) {
  result <- new.env(parent = emptyenv())
  result$done <- FALSE
  result$code <- NULL
  result$error <- NULL

  app <- list(call = function(request) {
    if (!identical(request$PATH_INFO, "/auth/callback")) {
      return(list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "Not found"))
    }

    query <- codex_parse_query(request$QUERY_STRING)
    callback <- codex_callback_result(query, expected_state)
    result$error <- callback$error
    result$code <- callback$code
    result$done <- TRUE

    ok <- is.null(result$error)
    list(
      status = if (ok) 200L else 400L,
      headers = list("Content-Type" = "text/html; charset=utf-8"),
      body = codex_callback_html(ok)
    )
  })

  server <- tryCatch(
    httpuv::startServer("127.0.0.1", codex_callback_port(), app),
    error = function(error) {
      rlang::abort(
        sprintf(
          "Could not bind the required OAuth callback at 127.0.0.1:%d. Close any process using that port and try again.",
          codex_callback_port()
        ),
        class = "codex_oauth_callback_error"
      )
    }
  )
  on.exit(httpuv::stopServer(server), add = TRUE)

  # Start listening before opening the browser. Fast local redirects can
  # otherwise arrive before the callback socket exists.
  if (is.function(on_ready)) on_ready()

  started <- Sys.time()
  while (!isTRUE(result$done)) {
    httpuv::service(timeoutMs = 100L)
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) >= timeout) {
      rlang::abort(
        "Timed out waiting for the OAuth browser callback.",
        class = "codex_oauth_timeout"
      )
    }
  }

  if (!is.null(result$error)) {
    rlang::abort(result$error, class = "codex_oauth_callback_error")
  }
  result$code
}

codex_token_response <- function(response, operation) {
  status <- httr2::resp_status(response)
  if (status < 200L || status >= 300L) {
    rlang::abort(
      sprintf("Codex OAuth %s failed (HTTP %d). Please authenticate again.", operation, status),
      class = paste0("codex_", operation, "_error")
    )
  }

  value <- tryCatch(httr2::resp_body_json(response, simplifyVector = TRUE),
    error = function(error) NULL
  )
  valid_access_token <- is.list(value) && is.character(value$access_token) &&
    length(value$access_token) == 1L && nzchar(value$access_token)
  if (!valid_access_token) {
    rlang::abort(
      sprintf("Codex OAuth %s returned a malformed credential response.", operation),
      class = paste0("codex_", operation, "_error")
    )
  }
  value
}

codex_jwt_claims <- function(token) {
  parts <- strsplit(token, ".", fixed = TRUE)[[1L]]
  if (length(parts) != 3L) return(NULL)
  tryCatch(
    jsonlite::fromJSON(rawToChar(codex_base64url_decode(parts[[2L]])), simplifyVector = TRUE),
    error = function(error) NULL
  )
}

codex_account_id <- function(access_token, id_token = NULL) {
  candidates <- Filter(Negate(is.null), list(id_token, access_token))
  for (token in candidates) {
    claims <- codex_jwt_claims(token)
    if (!is.list(claims)) next
    namespaced <- claims[["https://api.openai.com/auth"]]
    account_id <- if (is.list(namespaced)) namespaced$chatgpt_account_id else NULL
    account_id <- account_id %||% claims$chatgpt_account_id
    if (is.character(account_id) && length(account_id) == 1L && nzchar(account_id)) {
      return(account_id)
    }
  }
  rlang::abort(
    "The OAuth credential did not contain the account identifier required by the Codex transport.",
    class = "codex_account_error"
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

codex_auth_from_tokens <- function(tokens, previous = NULL) {
  refresh_token <- tokens$refresh_token %||% previous$refresh_token
  id_token <- tokens$id_token %||% previous$id_token
  if (!is.character(refresh_token) || length(refresh_token) != 1L || !nzchar(refresh_token)) {
    rlang::abort(
      "The OAuth credential response did not contain a refresh token.",
      class = "codex_token_exchange_error"
    )
  }

  expires_in <- suppressWarnings(as.numeric(tokens$expires_in %||% 0))
  if (length(expires_in) != 1L || !is.finite(expires_in) || expires_in < 0) expires_in <- 0
  expires_at <- as.numeric(Sys.time()) + expires_in
  account_id <- codex_account_id(tokens$access_token, id_token)

  structure(
    list(
      access_token = tokens$access_token,
      refresh_token = refresh_token,
      id_token = id_token,
      account_id = account_id,
      expires_at = expires_at
    ),
    class = c("codex_auth", "list")
  )
}

print.codex_auth <- function(x, ...) {
  info <- codex_account(x)
  print(info, ...)
  invisible(x)
}

codex_account <- function(auth = NULL) {
  if (is.null(auth)) auth <- codex_credentials_load()
  stopifnot(inherits(auth, "codex_auth"))
  data.frame(
    authenticated = TRUE,
    account = "<redacted>",
    expires_at = as.POSIXct(codex_token_expires_at(auth), origin = "1970-01-01", tz = "UTC")
  )
}

codex_token_expires_at <- function(auth) {
  claims <- codex_jwt_claims(auth$access_token)
  jwt_exp <- suppressWarnings(as.numeric(claims$exp %||% NA_real_))
  if (length(jwt_exp) == 1L && is.finite(jwt_exp)) jwt_exp else as.numeric(auth$expires_at)
}

codex_token_expired <- function(auth, skew = 60, now = as.numeric(Sys.time())) {
  expires_at <- codex_token_expires_at(auth)
  !is.finite(expires_at) || expires_at <= (now + skew)
}

codex_exchange_code <- function(code, verifier) {
  request <- httr2::request(codex_token_url()) |>
    httr2::req_body_form(
      grant_type = "authorization_code",
      code = code,
      redirect_uri = codex_redirect_uri(),
      client_id = codex_oauth_client_id(),
      code_verifier = verifier
    ) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) {
    rlang::abort(
      "Codex OAuth token exchange failed because of a network error.",
      class = "codex_token_exchange_error"
    )
  })
  codex_token_response(response, "token_exchange")
}

codex_refresh <- function(auth, persist = TRUE) {
  request <- httr2::request(codex_token_url()) |>
    httr2::req_body_form(
      grant_type = "refresh_token",
      refresh_token = auth$refresh_token,
      client_id = codex_oauth_client_id()
    ) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(httr2::req_perform(request), error = function(error) {
    rlang::abort(
      "Codex credential refresh failed because of a network error; run codex_login() if it persists.",
      class = "codex_refresh_error"
    )
  })
  tokens <- codex_token_response(response, "refresh")
  refreshed <- codex_auth_from_tokens(tokens, previous = auth)
  if (persist) codex_credentials_store(refreshed)
  refreshed
}

codex_auth <- function(force_refresh = FALSE) {
  auth <- codex_credentials_load()
  if (force_refresh || codex_token_expired(auth)) codex_refresh(auth) else auth
}

codex_open_browser <- function(url) {
  tryCatch(
    utils::browseURL(url, verbose = FALSE),
    error = function(error) {
      rlang::abort(
        "Could not open a browser for Codex authentication.",
        class = "codex_oauth_browser_error"
      )
    }
  )
  invisible(TRUE)
}

codex_login <- function(persist = TRUE, timeout = 300) {
  pkce <- codex_pkce()
  state <- codex_oauth_state()
  authorization_url <- codex_authorize_url(pkce, state)

  code <- codex_wait_for_callback(
    state,
    timeout = timeout,
    on_ready = function() codex_open_browser(authorization_url)
  )
  tokens <- codex_exchange_code(code, pkce$verifier)
  auth <- codex_auth_from_tokens(tokens)
  if (persist) codex_credentials_store(auth)
  auth
}

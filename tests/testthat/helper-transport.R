fake_codex_auth <- function() {
  structure(
    list(
      client_id = "oaiapp_fixtureclient",
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      expires_at = as.numeric(Sys.time()) + 3600,
      scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    ),
    class = c("codex_auth", "list")
  )
}

# Register cleanup in the caller's frame (testthat 3.0 has no exported defer).
fixture_defer <- function(expr, envir = parent.frame()) {
  thunk <- as.call(list(function() expr))
  do.call(base::on.exit, list(thunk, TRUE, FALSE), envir = envir)
}

# Point the package credential directory (and httr2's legacy cache) at a
# temporary directory so tests never touch the user's files.
local_codex_home <- function(env = parent.frame()) {
  home <- tempfile("ellmercodex-home-")
  old <- Sys.getenv(c("ELLMERCODEX_HOME", "HTTR2_OAUTH_CACHE"), unset = NA_character_)
  Sys.setenv(ELLMERCODEX_HOME = home, HTTR2_OAUTH_CACHE = file.path(home, "httr2"))
  withr_restore <- function() {
    for (name in names(old)) {
      if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, as.list(old[name]))
    }
    unlink(home, recursive = TRUE, force = TRUE)
    getFromNamespace("codex_session_clear", "ellmercodex")()
  }
  fixture_defer(withr_restore(), envir = env)
  home
}

fixture_token_response <- function(...) {
  utils::modifyList(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      id_token = "fixture-id-token",
      token_type = "Bearer",
      expires_in = 3600,
      scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    ),
    list(...)
  )
}

fixture_base64url <- function(value) {
  encoded <- openssl::base64_encode(charToRaw(value))
  sub("=+$", "", chartr("+/", "-_", encoded))
}

fixture_chunk_text <- function(chunk) {
  if (is.character(chunk)) return(paste0(chunk, collapse = ""))
  if (inherits(chunk, "ellmer::ContentText")) return(chunk@text)
  ""
}

fixture_text <- function(name) {
  path <- testthat::test_path("fixtures", name)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

fixture_stream_response <- function(name) {
  connection <- rawConnection(
    charToRaw(paste0(fixture_text(name), "\n\n")),
    "rb"
  )
  body <- getFromNamespace("StreamingBody", "httr2")$new(connection)
  getFromNamespace("new_response", "httr2")(
    method = "POST",
    url = "http://127.0.0.1:1",
    status_code = 200L,
    headers = list(`Content-Type` = "text/event-stream"),
    body = body
  )
}

await_promise <- function(promise, max_steps = 200L) {
  testthat::skip_if_not_installed("later")
  state <- new.env(parent = emptyenv())
  state$done <- FALSE
  state$value <- NULL
  state$error <- NULL
  promises::then(
    promise,
    function(value) {
      state$value <- value
      state$done <- TRUE
      invisible(value)
    },
    function(error) {
      state$error <- error
      state$done <- TRUE
      invisible(NULL)
    }
  )
  for (i in seq_len(max_steps)) {
    later::run_now(0.01)
    if (isTRUE(state$done)) break
  }
  if (!isTRUE(state$done)) {
    stop("The fixture promise did not settle.")
  }
  list(value = state$value, error = state$error)
}

new_async_fixture_chat <- function() {
  auth <- structure(
    list(access_token = "fixture-access-token", client_id = "oaiapp_fixtureclient"),
    class = c("codex_auth", "list")
  )
  codex_ellmer_chat_openai <- getFromNamespace("codex_ellmer_chat_openai", "ellmercodex")
  codex_patch_chat <- getFromNamespace("codex_patch_chat", "ellmercodex")
  codex_patch_chat(codex_ellmer_chat_openai(model = "fixture-model", auth = auth))
}

# On CRAN only, skip chat tests when the installed ellmer no longer matches the
# private Chat contracts that ellmercodex patches. Local and CI runs (NOT_CRAN
# set) still fail loudly so contract drift is caught before release.
skip_if_ellmer_contract_changed <- function() {
  testthat::skip_if_not_installed("ellmer")
  if (identical(Sys.getenv("NOT_CRAN"), "true")) return(invisible(TRUE))
  compatible <- tryCatch(
    {
      codex_patch_chat(codex_ellmer_chat_openai(
        model = "fixture-model",
        auth = fake_codex_auth()
      ))
      TRUE
    },
    codex_ellmer_compatibility_error = function(error) FALSE
  )
  if (!compatible) {
    testthat::skip("Installed ellmer changed private Chat contracts used by ellmercodex.")
  }
  invisible(TRUE)
}

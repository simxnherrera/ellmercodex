fake_codex_auth <- function() {
  structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      account_id = "fixture-account-id",
      expires_at = as.numeric(Sys.time()) + 3600
    ),
    class = c("codex_auth", "list")
  )
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
    list(access_token = "fixture-access-token", account_id = "fixture-account"),
    class = c("codex_auth", "list")
  )
  codex_ellmer_chat_openai <- getFromNamespace("codex_ellmer_chat_openai", "ellmercodex")
  codex_patch_chat <- getFromNamespace("codex_patch_chat", "ellmercodex")
  codex_patch_chat(codex_ellmer_chat_openai(model = "fixture-model", auth = auth))
}

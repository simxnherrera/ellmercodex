# Live check for the "Sign in with ChatGPT" flow.
#
# Run it yourself, interactively, from the package root:
#
#   ELLMERCODEX_RUN_LIVE_TESTS=true R
#   > devtools::load_all()            # or library(ellmercodex)
#   > source("inst/manual-tests/siwc-live.R")
#
# It opens your browser once for sign-in. It never prints tokens, client IDs,
# or host IDs; comparisons use short SHA-256 fingerprints. By default it uses
# a separate credential directory so your normal ellmercodex credential is not
# touched. Paste the summary table at the end into the conversation.
#
# Optional environment variables:
#   ELLMERCODEX_SIWC_HOME     credential directory (default ~/.ellmercodex-siwc-test)
#   ELLMERCODEX_MODEL         model to use instead of the catalog default
#   ELLMERCODEX_SIWC_REAUTH   "true" to also test reauthorization (second browser visit)
#   ELLMERCODEX_SIWC_LOGOUT   "true" to revoke and delete the credential at the end

if (!identical(tolower(Sys.getenv("ELLMERCODEX_RUN_LIVE_TESTS")), "true")) {
  stop("Set ELLMERCODEX_RUN_LIVE_TESTS=true to opt in to live checks.", call. = FALSE)
}
if (!interactive()) {
  stop("Run this script in an interactive R session; it opens a browser.", call. = FALSE)
}
if (!"ellmercodex" %in% loadedNamespaces()) library(ellmercodex)

home <- Sys.getenv("ELLMERCODEX_SIWC_HOME", unset = path.expand("~/.ellmercodex-siwc-test"))
Sys.setenv(ELLMERCODEX_HOME = home)
message("Credential directory for this check: ", home)

ns <- asNamespace("ellmercodex")
fingerprint <- function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) return(NA_character_)
  substr(as.character(openssl::sha256(x)), 1L, 8L)
}
results <- data.frame(step = character(), status = character(), detail = character())
run_step <- function(step, code) {
  message("\n== ", step)
  detail <- tryCatch(
    {
      value <- force(code)
      if (is.character(value) && length(value) == 1L) value else "ok"
    },
    error = function(error) {
      structure(
        paste0(class(error)[[1L]], ": ", ns$codex_redact(conditionMessage(error))),
        failed = TRUE
      )
    }
  )
  status <- if (isTRUE(attr(detail, "failed"))) "FAIL" else "PASS"
  message(status, " - ", detail)
  results[nrow(results) + 1L, ] <<- list(step, status, as.character(detail))
  invisible(status == "PASS")
}
check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

run_step("1. codex_available()", {
  check(codex_available(), "codex_available() returned FALSE")
  paste("ellmercodex", utils::packageVersion("ellmercodex"))
})

first_client <- NA_character_
run_step("2. codex_login() in the browser", {
  ns$codex_session_clear()
  auth <- codex_login(persist = TRUE, timeout = 300)
  check(isTRUE(codex_account()$authenticated), "codex_account() is not authenticated")
  check(startsWith(auth$client_id, "oaiapp_"), "issued client_id does not start with oaiapp_")
  check(ns$codex_scope_granted(auth$scope), "chatgpt.tokens.use.direct was not granted")
  host_id <- ns$codex_host_id(create = FALSE)
  check(grepl("^urn:uuid:", host_id), "host-id is missing or malformed")
  stored <- jsonlite::fromJSON(file.path(home, "credentials.json"))
  check(identical(stored$client_id, auth$client_id), "stored client_id differs")
  mode <- format(file.info(file.path(home, "credentials.json"))$mode)
  first_client <<- fingerprint(auth$client_id)
  sprintf(
    "client %s, host %s, file mode %s, expires %s",
    first_client, fingerprint(host_id), mode,
    format(codex_account()$expires_at, tz = "UTC")
  )
})

models <- NULL
run_step("3. codex_models()", {
  models <<- codex_models()
  check(nrow(models) > 0L, "codex_models() returned no listed models")
  paste(utils::head(models$id, 8L), collapse = ", ")
})

model <- Sys.getenv("ELLMERCODEX_MODEL", unset = "")
if (!nzchar(model)) model <- NULL

run_step("4. chat_codex()$chat() with a system prompt", {
  chat <- chat_codex(system_prompt = "Follow the user's output instructions exactly.", model = model)
  answer <- as.character(chat$chat("Say exactly: Hello, world!"))
  check(nzchar(answer), "empty answer")
  paste0("model ", chat$get_model(), ": ", substr(answer, 1L, 60L))
})

run_step("5. Streaming with $stream()", {
  chat <- chat_codex(model = model)
  chunks <- character()
  coro::loop(for (chunk in chat$stream("Count from 1 to 5, one number per line.")) {
    chunks <- c(chunks, chunk)
  })
  check(length(chunks) > 0L && nzchar(paste(chunks, collapse = "")), "no streamed text")
  sprintf("%d chunks, %d characters", length(chunks), nchar(paste(chunks, collapse = "")))
})

run_step("6. Tool call", {
  chat <- chat_codex(model = model)
  calls <- character()
  chat$register_tool(ellmer::tool(
    function(city) {
      calls <<- c(calls, city)
      paste("Sunny and 18 C in", city)
    },
    name = "get_weather",
    description = "Get the current weather for a city.",
    arguments = list(city = ellmer::type_string("City name."))
  ))
  answer <- as.character(chat$chat("Use the get_weather tool for Montevideo, then report the result."))
  check(length(calls) >= 1L, "the model did not call the tool")
  sprintf("tool called %d time(s) with %s; answer: %s", length(calls), calls[[1L]], substr(answer, 1L, 60L))
})

run_step("7. Structured output", {
  chat <- chat_codex(model = model)
  person <- chat$chat_structured(
    "Ana is 34 years old.",
    type = ellmer::type_object(name = ellmer::type_string(), age = ellmer::type_integer())
  )
  check(identical(person$name, "Ana") && identical(as.integer(person$age), 34L), "unexpected structured result")
  sprintf("name=%s, age=%s", person$name, person$age)
})

run_step("8. Token refresh and rotation", {
  before <- ns$codex_auth()
  after <- ns$codex_auth(force_refresh = TRUE)
  check(!identical(before$access_token, after$access_token), "access token did not change")
  stored <- jsonlite::fromJSON(file.path(home, "credentials.json"))
  check(identical(stored$refresh_token, after$refresh_token), "rotated refresh token was not stored")
  answer <- as.character(chat_codex(model = model)$chat("Reply with the single word ok."))
  check(nzchar(answer), "chat after refresh returned empty text")
  sprintf(
    "access %s -> %s, refresh rotated: %s, chat after refresh: %s",
    fingerprint(before$access_token), fingerprint(after$access_token),
    !identical(before$refresh_token, after$refresh_token), substr(answer, 1L, 20L)
  )
})

run_step("9. Prohibited parameter fails locally", {
  chat <- chat_codex(model = model, params = ellmer::params(temperature = 0))
  error <- tryCatch(chat$chat("Hi"), codex_chat_argument_error = identity)
  check(inherits(error, "codex_chat_argument_error"), "temperature was not rejected locally")
  "temperature rejected before the request"
})

if (identical(tolower(Sys.getenv("ELLMERCODEX_SIWC_REAUTH")), "true")) {
  run_step("10. Reauthorization reuses the registration", {
    ns$codex_session_clear()
    auth <- codex_login(persist = TRUE)
    check(identical(fingerprint(auth$client_id), first_client), "a new client_id was issued")
    paste("same client", first_client)
  })
}

if (identical(tolower(Sys.getenv("ELLMERCODEX_SIWC_LOGOUT")), "true")) {
  run_step("11. codex_logout() revokes and removes", {
    warning_seen <- FALSE
    withCallingHandlers(
      codex_logout(),
      codex_revocation_warning = function(w) {
        warning_seen <<- TRUE
        invokeRestart("muffleWarning")
      }
    )
    check(!file.exists(file.path(home, "credentials.json")), "credentials.json still exists")
    check(file.exists(file.path(home, "host-id")), "host-id was removed")
    if (warning_seen) "removed locally; remote revocation FAILED (warning)" else "revoked and removed"
  })
}

message("\n==== Summary (paste this) ====")
print(results, right = FALSE, row.names = FALSE)

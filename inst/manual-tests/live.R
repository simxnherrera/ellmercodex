# This script is deliberately excluded from automated package checks. It makes
# authenticated requests only after an exact, explicit environment opt-in.
enabled <- identical(
  tolower(Sys.getenv("ELLMERCODEX_RUN_LIVE_TESTS", unset = "false")),
  "true"
)
if (!enabled) {
  stop(
    paste(
      "Live compatibility checks are disabled.",
      "Set ELLMERCODEX_RUN_LIVE_TESTS=true to opt in."
    ),
    call. = FALSE
  )
}

library(ellmercodex)

if (!codex_available()) {
  stop("The local ellmercodex compatibility check failed.", call. = FALSE)
}

account <- codex_account()
force_login <- identical(
  tolower(Sys.getenv("ELLMERCODEX_LIVE_EXPLICIT_LOGIN", unset = "false")),
  "true"
)
if (force_login || !isTRUE(account$authenticated[[1L]])) {
  auth <- codex_login(persist = FALSE)
  account <- codex_account()
}
print(account)

models <- codex_models()
if (nrow(models) == 0L) {
  stop("codex_models() returned no selectable models.", call. = FALSE)
}

model <- Sys.getenv("ELLMERCODEX_MODEL", unset = "")
if (!nzchar(model)) {
  usable <- which(!is.na(models$supported_in_api) & models$supported_in_api)
  if (length(usable) == 0L) stop("No usable live model was advertised.", call. = FALSE)
  model <- models$id[[usable[[1L]]]]
}
selected <- models[match(model, models$id), , drop = FALSE]
if (nrow(selected) != 1L || !isTRUE(selected$supported_in_api[[1L]])) {
  stop("The selected live model is not marked usable by codex_models().", call. = FALSE)
}

default_chat <- chat_codex(model = NULL)
if (!default_chat$get_model() %in% models$id) {
  stop("chat_codex(model = NULL) selected a model absent from codex_models().", call. = FALSE)
}

chat <- chat_codex(
  system_prompt = "Reply briefly and follow the requested output format.",
  model = model
)
first <- as.character(chat$chat(
  "Remember that the codeword is amber. Include the word acknowledged in your reply."
))
second <- as.character(chat$chat(
  "What was the codeword? Reply with only the codeword."
))

if (!nzchar(first) || !nzchar(second)) {
  stop("The live chat returned empty text.", call. = FALSE)
}
turns <- chat$get_turns()
if (!is.list(turns) || length(turns) < 4L) {
  stop("The live chat did not retain the expected multi-turn history.", call. = FALSE)
}

message("Live compatibility check passed with ", length(turns), " retained turns.")

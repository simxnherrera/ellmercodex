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
if (!isTRUE(account$authenticated[[1L]])) {
  codex_login()
  account <- codex_account()
}
print(account)

model <- Sys.getenv("ELLMERCODEX_MODEL", unset = "")
if (!nzchar(model)) {
  stop("Set ELLMERCODEX_MODEL to an account-eligible model.", call. = FALSE)
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

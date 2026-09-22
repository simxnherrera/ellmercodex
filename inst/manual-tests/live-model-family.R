# This script is deliberately excluded from automated package checks. It makes
# authenticated requests only after an exact, explicit environment opt-in.
enabled <- identical(
  tolower(Sys.getenv("ELLMERCODEX_RUN_LIVE_TESTS", unset = "false")),
  "true"
)
if (!enabled) {
  stop(
    "Live model checks are disabled. Set ELLMERCODEX_RUN_LIVE_TESTS=true to opt in.",
    call. = FALSE
  )
}

library(ellmercodex)

account <- codex_account()
if (!isTRUE(account$authenticated[[1L]])) {
  stop("Sign in with codex_login() before running the live model check.", call. = FALSE)
}

models <- c("gpt-6-astra", "gpt-6-sol", "gpt-6-luna")
results <- lapply(models, function(model) {
  chat <- chat_codex(model = model, effort = "medium", echo = "none")
  response <- as.character(chat$chat("Reply with a short confirmation."))
  if (length(response) != 1L || is.na(response) || !nzchar(response)) {
    stop("The live model returned no text: ", model, call. = FALSE)
  }
  model
})

cat("GPT-6 family live checks passed:\n")
cat(paste0("- ", unlist(results), collapse = "\n"), "\n", sep = "")

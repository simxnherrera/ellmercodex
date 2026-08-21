# Unstable protocol configuration for the scratch proof of concept.
#
# Sources and support status are recorded in docs/feasibility.md. None of the
# values in this file are secrets. The OAuth and transport values are observed
# in OpenAI's open-source Codex client and in Pi; they are not a documented
# public OAuth/HTTP API contract for arbitrary third-party clients.

codex_oauth_client_id <- function() {
  # Observed at openai/codex commit 21facf2 in
  # codex-rs/login/src/auth/manager.rs, and at earendil-works/pi commit 5cd93f6
  # in packages/ai/src/auth/oauth/openai-codex.ts. This is the public Codex
  # native-client identifier, not an ellmercodex-specific registration.
  "app_EMoamEEZ73f0CkXaXp7hrann"
}

codex_authorization_url <- function() {
  # Observed in the same OpenAI Codex and Pi OAuth implementations.
  "https://auth.openai.com/oauth/authorize"
}

codex_token_url <- function() {
  # Observed in the same OpenAI Codex and Pi OAuth implementations.
  "https://auth.openai.com/oauth/token"
}

codex_responses_url <- function() {
  # Undocumented direct subscription transport. Observed in Pi's
  # openai-codex-responses.ts and OpenCode's built-in Codex provider.
  "https://chatgpt.com/backend-api/codex/responses"
}

codex_protocol_version <- function() {
  # Observed compatibility header in Pi. This value is not documented as a
  # stable public protocol version.
  "responses=experimental"
}

codex_callback_port <- function() {
  # Required by the redirect registered to the observed public Codex client.
  1455L
}

codex_redirect_uri <- function() {
  sprintf("http://localhost:%d/auth/callback", codex_callback_port())
}

codex_originator <- function() {
  # Identify this client honestly; do not claim to be Pi, OpenCode, or Codex.
  "ellmercodex"
}

codex_default_model <- function() {
  model <- Sys.getenv("ELLMERCODEX_POC_MODEL", unset = "gpt-5.6-luna")
  if (!nzchar(model)) "gpt-5.6-luna" else model
}

codex_request_headers <- function(auth) {
  stopifnot(inherits(auth, "codex_auth"))

  c(
    Authorization = paste("Bearer", auth$access_token),
    `ChatGPT-Account-Id` = auth$account_id,
    originator = codex_originator(),
    `OpenAI-Beta` = codex_protocol_version(),
    Accept = "text/event-stream",
    `User-Agent` = "ellmercodex-poc/0.0.0"
  )
}

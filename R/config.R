# Centralized configuration for the observed Codex compatibility transport.
#
# These values are deliberately kept in one file.  The authorization and
# subscription transport endpoints are observed implementation details, not a
# documented public API.  Keeping them centralized makes an eventual migration
# to a repaired or documented direct surface auditable.

codex_oauth_client_id <- function() {
  # Observed in the openai/codex native client.  This is not an
  # ellmercodex-specific registration or a claim that arbitrary native clients
  # may reuse it.
  "app_EMoamEEZ73f0CkXaXp7hrann"
}

codex_authorization_url <- function() {
  "https://auth.openai.com/oauth/authorize"
}

codex_token_url <- function() {
  "https://auth.openai.com/oauth/token"
}

codex_responses_url <- function() {
  # Undocumented direct subscription transport observed in independent clients.
  "https://chatgpt.com/backend-api/codex/responses"
}

codex_models_endpoint <- function() {
  # The account-specific model catalog is an observed sibling of Responses.
  paste0(sub("/responses$", "", codex_responses_url()), "/models")
}

codex_protocol_version <- function() {
  # Observed compatibility header; not a stable public protocol guarantee.
  "responses=experimental"
}

codex_callback_port <- function() {
  # The registered redirect URI currently uses this compatibility-sensitive port.
  1455L
}

codex_redirect_uri <- function() {
  sprintf("http://localhost:%d/auth/callback", codex_callback_port())
}

codex_originator <- function() {
  # Identify this package honestly.  Never impersonate Codex, Pi, or another
  # client in an authorization or generation request.
  "ellmercodex"
}

codex_default_model <- function() {
  # Model availability is account- and service-specific.  The environment
  # override is useful for an explicitly selected model; it is not discovery.
  model <- Sys.getenv("ELLMERCODEX_MODEL", unset = "gpt-5.6-luna")
  if (!is.character(model) || length(model) != 1L || !nzchar(model)) {
    "gpt-5.6-luna"
  } else {
    model
  }
}

codex_user_agent <- function() {
  version <- tryCatch(
    as.character(utils::packageVersion("ellmercodex")),
    error = function(error) "0.1.3"
  )
  paste0("ellmercodex/", version)
}

codex_auth_field <- function(auth, ...) {
  fields <- c(...)
  if (!is.list(auth)) {
    return(NULL)
  }
  for (field in fields) {
    value <- auth[[field]]
    if (is.character(value) && length(value) == 1L && nzchar(value)) {
      return(value)
    }
  }
  NULL
}

codex_request_headers <- function(auth) {
  access_token <- codex_auth_field(auth, "access_token", "accessToken")
  account_id <- codex_auth_field(
    auth,
    "account_id",
    "chatgpt_account_id",
    "chatgptAccountId"
  )

  if (is.null(access_token) || is.null(account_id)) {
    rlang::abort(
      "The Codex credential is missing the routing fields required by the transport.",
      class = "codex_authentication_error"
    )
  }

  c(
    Authorization = paste("Bearer", access_token),
    `ChatGPT-Account-Id` = account_id,
    originator = codex_originator(),
    `OpenAI-Beta` = codex_protocol_version(),
    Accept = "text/event-stream",
    `User-Agent` = codex_user_agent()
  )
}

# Centralized configuration for the documented "Sign in with ChatGPT" flow.
#
# These values follow OpenAI's ChatGPT plan usage documentation for
# open-source and locally hosted apps:
# https://developers.openai.com/siwc/token-sharing-open-source
# Keeping them in one file makes protocol changes auditable.

codex_oauth_issuer <- function() {
  "https://auth.openai.com"
}

codex_oidc_discovery_url <- function() {
  paste0(codex_oauth_issuer(), "/.well-known/openid-configuration")
}

codex_dynamic_client_id <- function() {
  # First-time registration uses this documented placeholder. The callback
  # returns the issued, user- and workspace-bound client ID, which is used for
  # the code exchange, refreshes, and later reauthorization.
  "dynamic_agent_client"
}

codex_agent_name <- function() {
  # Sent as `agent_name_hint` on first registration only. It names this
  # package honestly; never impersonate another client.
  "ellmercodex"
}

codex_authorization_url <- function() {
  "https://auth.openai.com/api/accounts/authorize"
}

codex_token_url <- function() {
  "https://auth.openai.com/api/accounts/oauth/token"
}

codex_oauth_scope <- function() {
  "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
}

codex_plan_scope <- function() {
  # Required before inference with the ChatGPT plan.
  "chatgpt.tokens.use.direct"
}

codex_api_base_url <- function() {
  "https://api.openai.com/v1"
}

codex_oauth_resource <- function() {
  codex_api_base_url()
}

codex_responses_url <- function() {
  paste0(codex_api_base_url(), "/responses")
}

codex_models_endpoint <- function() {
  paste0(codex_api_base_url(), "/models")
}

codex_callback_port <- function() {
  # Only the port may vary between sign-ins. A fixed default keeps SSH port
  # forwarding predictable; ELLMERCODEX_CALLBACK_PORT overrides it.
  value <- Sys.getenv("ELLMERCODEX_CALLBACK_PORT", unset = "")
  port <- suppressWarnings(as.integer(value))
  if (length(port) == 1L && !is.na(port) && port >= 1024L && port <= 65535L) {
    port
  } else {
    1455L
  }
}

codex_redirect_uri <- function(port = codex_callback_port()) {
  # The documentation requires the IPv4 loopback literal (never `localhost`)
  # and the `/callback` path.
  sprintf("http://127.0.0.1:%d/callback", as.integer(port))
}

codex_default_model <- function() {
  # This is an explicit operator override, not a package catalog. When it is
  # absent, chat_codex() resolves a model from the authenticated catalog.
  model <- Sys.getenv("ELLMERCODEX_MODEL", unset = "")
  if (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model)) {
    NULL
  } else {
    model
  }
}

codex_user_agent <- function() {
  version <- tryCatch(
    as.character(utils::packageVersion("ellmercodex")),
    error = function(error) "0.2.0"
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

codex_transport_headers <- function() {
  # The public Responses API needs only the bearer token. These headers are
  # centralized so model discovery and Chat requests cannot drift apart.
  c(
    Accept = "text/event-stream",
    `User-Agent` = codex_user_agent()
  )
}

codex_request_headers <- function(auth) {
  access_token <- codex_auth_field(auth, "access_token")

  if (is.null(access_token)) {
    rlang::abort(
      "The Codex credential is missing the access token required by the transport.",
      class = "codex_authentication_error"
    )
  }

  c(
    Authorization = paste("Bearer", access_token),
    codex_transport_headers()
  )
}

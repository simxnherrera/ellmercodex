#' ellmercodex condition classes
#'
#' ellmercodex signals structured conditions so callers can handle failures
#' without parsing messages. Messages are sanitized and never intentionally
#' include tokens, authorization codes, OAuth state, account identifiers, or
#' credential-store contents.
#'
#' Authentication and credential conditions inherit from `codex_auth_error`.
#' The principal subclasses are `codex_auth_missing`,
#' `codex_auth_argument_error`, `codex_oauth_argument_error`,
#' `codex_oauth_callback_error`, `codex_oauth_browser_error`,
#' `codex_oauth_timeout`, `codex_token_exchange_error`,
#' `codex_refresh_error`, `codex_account_error`, and
#' `codex_credential_store_error`.
#'
#' Transport and stream conditions are `codex_request_error`,
#' `codex_authentication_error`, `codex_rate_limit_error`,
#' `codex_model_unavailable_error`, `codex_malformed_request_error`,
#' `codex_server_error`, `codex_network_error`, `codex_protocol_error`,
#' `codex_protocol_changed_error`, `codex_generation_error`, and
#' `codex_incomplete_error`.
#'
#' ellmer integration conditions are `codex_chat_argument_error`,
#' `codex_chat_error`, `codex_ellmer_missing`, and
#' `codex_ellmer_compatibility_error`.
#'
#' @aliases codex_auth_error codex_auth_missing codex_auth_argument_error codex_oauth_argument_error codex_oauth_callback_error codex_oauth_browser_error codex_oauth_timeout codex_token_exchange_error codex_refresh_error codex_account_error codex_credential_store_error codex_request_error codex_authentication_error codex_rate_limit_error codex_model_unavailable_error codex_malformed_request_error codex_server_error codex_network_error codex_protocol_error codex_protocol_changed_error codex_generation_error codex_incomplete_error codex_chat_argument_error codex_chat_error codex_ellmer_missing codex_ellmer_compatibility_error
#' @name ellmercodex-conditions
NULL

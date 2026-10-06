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
#' `codex_oauth_callback_error`,
#' `codex_oauth_timeout`, `codex_token_exchange_error`,
#' `codex_refresh_error`, `codex_account_error`,
#' `codex_credential_store_error`, and `codex_plan_scope_error` (ChatGPT plan
#' usage, the `chatgpt.tokens.use.direct` scope, was not granted). Refresh
#' and token-exchange errors carry the OAuth error code in an `oauth_error`
#' field when the server returned one. `codex_logout()` signals the warning
#' `codex_revocation_warning` when remote revocation fails.
#'
#' Transport and stream conditions are `codex_request_error`,
#' `codex_authentication_error`, `codex_rate_limit_error`,
#' `codex_model_unavailable_error`, `codex_malformed_request_error`,
#' `codex_server_error`, `codex_network_error`, `codex_protocol_error`,
#' `codex_protocol_changed_error`, `codex_generation_error`, and
#' `codex_incomplete_error`.
#'
#' Documented ChatGPT plan usage error codes map to more specific subclasses
#' that keep the parents above, and carry the server's `code` and `param`
#' fields: `codex_usage_limit_error` (`subscription_sharing_usage_limit_exceeded`;
#' also a `codex_rate_limit_error`), `codex_usage_unavailable_error`
#' (`subscription_sharing_usage_unavailable` and
#' `subscription_sharing_user_unavailable`; also a `codex_server_error`),
#' `codex_plan_ineligible_error` (`subscription_sharing_user_not_eligible`;
#' also a `codex_authentication_error`), and
#' `codex_unsupported_capability_error`
#' (`subscription_sharing_unsupported_capability`; also a
#' `codex_malformed_request_error`).
#'
#' ellmer integration conditions are `codex_chat_argument_error`,
#' `codex_chat_error`, `codex_model_selection_error`, `codex_ellmer_missing`, and
#' `codex_ellmer_compatibility_error`.
#'
#' Handle these classes with condition handlers rather than matching their
#' messages. More specific subclasses can be handled before the common
#' `codex_auth_error` or `codex_request_error` parents.
#'
#' @aliases codex_auth_error codex_auth_missing codex_auth_argument_error codex_oauth_argument_error codex_oauth_callback_error codex_oauth_timeout codex_token_exchange_error codex_refresh_error codex_account_error codex_credential_store_error codex_plan_scope_error codex_revocation_warning codex_request_error codex_authentication_error codex_rate_limit_error codex_model_unavailable_error codex_malformed_request_error codex_server_error codex_network_error codex_protocol_error codex_protocol_changed_error codex_generation_error codex_incomplete_error codex_usage_limit_error codex_usage_unavailable_error codex_plan_ineligible_error codex_unsupported_capability_error codex_chat_argument_error codex_chat_error codex_model_selection_error codex_ellmer_missing codex_ellmer_compatibility_error
#' @name ellmercodex-conditions
#' @examples
#' error <- tryCatch(
#'   codex_available(NA),
#'   codex_auth_argument_error = identity
#' )
#' inherits(error, "codex_auth_error")
NULL

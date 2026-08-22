#' ellmercodex: Codex integration for ellmer
#'
#' `ellmercodex` provides a stable, explicitly bounded core integration between
#' [ellmer][ellmer::chat_openai] and subscription-backed Codex authentication.
#' The stable compatibility target is the complete public ellmer 0.4.2 `Chat`
#' object for interactive, single-conversation operations. The direct OAuth
#' endpoints and Responses endpoint used by this package are undocumented
#' compatibility observations, may change without notice, and are not an
#' OpenAI-supported public API. This package is independent and is not
#' affiliated with or endorsed by OpenAI.
#'
#' Authentication is never started as a package-loading side effect. Call
#' [codex_login()] explicitly before [chat_codex()] when no stored credential
#' is available. Examples and offline tests do not authenticate, open a
#' browser, read credentials, or make network requests.
#'
#' The usual workflow is to check [codex_available()], authenticate with
#' [codex_login()], inspect the account with [codex_account()], and then create
#' a chat with [chat_codex()]. [codex_models()] can be used after sign-in to
#' inspect the account-specific model catalog and its advertised reasoning
#' efforts. [codex_logout()] removes only the credential owned by this package.
#'
#' The public API is deliberately small: [codex_login()], [codex_logout()],
#' [codex_account()], [codex_models()], [codex_available()], and
#' [chat_codex()]. The chat compatibility layer is version-gated to the
#' inspected ellmer 0.4.2 public API and supports its complete Chat object:
#' text and content streaming, model parameters, per-model reasoning effort,
#' structured output, multi-turn history, rich image/PDF content, asynchronous
#' chat, tool loops, callbacks, cancellation, cloning, echo, and response
#' metadata. The separately exported ellmer parallel/batch helpers are outside
#' the stable core contract and are explicitly blocked for the Codex stream-only
#' endpoint rather than silently degraded.
#'
#' @section External service and compatibility:
#' The authentication and Responses transport are observed compatibility
#' surfaces rather than documented third-party APIs. They require an active
#' account and may change or become unavailable without notice. The package
#' does not claim affiliation with or endorsement by OpenAI.
#'
#' @keywords package
#' @docType package
#' @name ellmercodex
"_PACKAGE"

utils::globalVariables(c("private", "self"))

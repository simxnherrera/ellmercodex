#' ellmercodex: Experimental Codex integration for ellmer
#'
#' `ellmercodex` is an explicitly opt-in, experimental integration between
#' [ellmer][ellmer::chat_openai] and subscription-backed Codex authentication
#' and Responses transport behavior observed in current clients. The direct
#' OAuth endpoints and Responses endpoint used by this package are
#' undocumented compatibility observations, may change without notice, and
#' are not an OpenAI-supported public API. This package is independent and is
#' not affiliated with or endorsed by OpenAI.
#'
#' Authentication is never started as a package-loading side effect. Call
#' [codex_login()] explicitly before [chat_codex()] when no stored credential
#' is available. Examples and offline tests do not authenticate, open a
#' browser, read credentials, or make network requests.
#'
#' The public API is deliberately small: [codex_login()], [codex_logout()],
#' [codex_account()], [codex_models()], [codex_available()], and
#' [chat_codex()]. The chat compatibility layer is version-gated to the
#' inspected ellmer 0.4.2 public API and supports its complete Chat object:
#' text and content streaming, model parameters, per-model reasoning effort,
#' structured output, multi-turn history, rich image/PDF content, asynchronous
#' chat, tool loops, callbacks, cancellation, cloning, echo, and response
#' metadata. The separately exported ellmer parallel/batch helpers are
#' explicitly blocked for the Codex stream-only endpoint and prevent a
#' stable-status claim.
#'
#' @keywords internal
#' @docType package
#' @name ellmercodex
"_PACKAGE"

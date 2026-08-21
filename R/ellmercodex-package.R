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
#' [chat_codex()]. The chat compatibility layer is version-gated for the
#' ellmer 0.4.x public API and supports text streaming, model parameters,
#' per-model reasoning effort, structured output, and ordinary multi-turn
#' history. Registered ellmer function tools are supported through a
#' version-gated Codex Responses compatibility loop. Asynchronous methods are
#' not promised by this experimental package.
#'
#' @keywords internal
#' @docType package
#' @name ellmercodex
"_PACKAGE"

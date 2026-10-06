#' ellmercodex: Codex integration for ellmer
#'
#' `ellmercodex` provides a stable, explicitly bounded core integration between
#' [ellmer][ellmer::chat_openai] and a ChatGPT subscription. It uses
#' OpenAI's documented "Sign in with ChatGPT" flow for open-source, locally
#' hosted apps (<https://developers.openai.com/siwc/token-sharing-open-source>)
#' and the public Responses API. The stable compatibility target is the public
#' ellmer `Chat` (0.5.0 or later) object for interactive, single-conversation
#' operations. This package is independent and is not affiliated with or
#' endorsed by OpenAI.
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
#' [chat_codex()]. The chat compatibility layer is checked against the
#' required ellmer contracts at runtime and supports interactive Chat methods:
#' text and content streaming, model parameters, per-model reasoning effort,
#' structured output, multi-turn history, rich image/PDF content, asynchronous
#' chat, tool loops, callbacks, cancellation, cloning, echo, and response
#' metadata. Provider token counting and file management are unavailable.
#' The separately exported ellmer parallel/batch helpers are outside
#' the stable core contract and are explicitly blocked for the Codex stream-only
#' endpoint rather than silently degraded. ChatGPT plan usage also rejects some
#' Responses arguments, such as `temperature` and `max_output_tokens`; these
#' fail before a request is sent.
#'
#' @section External service and compatibility:
#' ChatGPT plan usage through "Sign in with ChatGPT" is a preview feature for
#' open-source and locally hosted apps; paid or remotely hosted apps need
#' OpenAI's approval. It requires an eligible ChatGPT plan and workspace, and
#' its limits and supported features may change. The package does not claim
#' affiliation with or endorsement by OpenAI.
#'
#' @keywords package
#' @docType package
#' @name ellmercodex
"_PACKAGE"

utils::globalVariables(c("private", "self"))

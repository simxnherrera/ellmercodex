codex_echo <- function(echo, default = "none") {
  if (is.null(echo)) echo <- default
  # A missing argument arrives as the usual choices vector. Match the first
  # choice explicitly so errors remain package conditions rather than base
  # `match.arg()` errors.
  if (is.character(echo) && length(echo) > 1L &&
        all(echo %in% c("none", "output", "all"))) {
    echo <- echo[[1L]]
  }
  if (isTRUE(echo)) echo <- "output"
  if (isFALSE(echo)) echo <- "none"
  if (identical(echo, "text")) echo <- "output"
  if (!is.character(echo) || length(echo) != 1L || is.na(echo) ||
        !echo %in% c("none", "output", "all")) {
    rlang::abort(
      "`echo` must be one of \"none\", \"output\", or \"all\".",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  echo
}

codex_chat_reasoning_effort <- function(effort, params) {
  param_effort <- if (is.list(params)) params$reasoning_effort else NULL
  values <- list(effort = effort, params = param_effort)
  values <- values[!vapply(values, is.null, logical(1))]
  if (length(values) == 0L) return(NULL)

  valid <- vapply(
    values,
    function(value) {
      is.character(value) && length(value) == 1L &&
        !is.na(value) && nzchar(value)
    },
    logical(1)
  )
  if (!all(valid)) {
    rlang::abort(
      "Reasoning effort must be NULL or one non-empty string, matching ellmer::params().",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  requested <- unname(values[[1L]])
  if (length(values) == 2L && !identical(requested, unname(values[[2L]]))) {
    rlang::abort(
      "`effort` and `params$reasoning_effort` must match when both are supplied.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  requested
}

codex_patch_chat <- function(chat, default_echo = "none") {
  if (!inherits(chat, "Chat")) {
    rlang::abort(
      "The installed ellmer factory did not return a Chat object.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  # Historical internal entry point retained for callers from 0.1.x. The
  # compatibility implementation itself is centralized in one module and
  # never replaces public Chat methods.
  codex_ellmer_compatibility()
  codex_install_private_submit_methods(chat)
}
#' Create a Codex chat backed by ellmer
#'
#' `chat_codex()` returns a normal ellmer `Chat` object configured for the
#' observed Codex subscription transport. It does not start browser
#' authentication. Call [codex_login()] explicitly first when no stored
#' credential is available; an existing credential is loaded and refreshed as
#' needed.
#'
#' The returned chat is the complete public `ellmer` 0.4.2 `Chat` object for
#' interactive, single-conversation operations, including ordinary and
#' structured chat, synchronous and asynchronous streaming, tool declarations
#' and multi-round execution, callbacks, cancellation, cloning, history, echo,
#' model/provider configuration, rich content, and response metadata. The
#' compatibility layer uses one version-gated provider/turn-submission seam
#' while leaving public Chat methods and ellmer lifecycle semantics intact.
#' The separate ellmer parallel/batch helpers are outside this stable core
#' contract. Parallel helpers use the package blocker, while batch helpers stop
#' in ellmer's generic unsupported-provider check because the Codex endpoint is
#' stream-only.
#'
#' `$chat_structured()` intentionally follows ellmer's semantics and disables
#' registered tools for that request. Call `$chat()` first when tool-assisted
#' context is needed, then use `$chat_structured()` to extract structured data.
#'
#' @param system_prompt Optional system prompt passed to ellmer.
#' @param model Optional Codex model name. If omitted, `chat_codex()` queries
#'   the authenticated account catalog and chooses its lowest-priority usable
#'   model. Set `ELLMERCODEX_MODEL` for an explicit environment override;
#'   model availability remains account- and workspace-specific. If discovery
#'   is empty or unavailable, construction fails with an actionable error.
#' @param effort Optional Codex reasoning effort. It is forwarded through
#'   ellmer's `reasoning_effort` parameter and must be one of the values
#'   advertised by [codex_models()] for the selected model.
#' @param params Optional ellmer model parameters, usually created with
#'   `ellmer::params()`. A supplied `reasoning_effort` must agree with
#'   `effort`, when both are provided.
#'   Other ellmer-supported model parameters are passed through unchanged.
#' @param api_args Optional named list of additional Responses arguments passed
#'   through ellmer on every request. This is an advanced escape hatch for
#'   arguments accepted by the observed transport; unsupported arguments may
#'   be rejected by the remote service.
#' @param echo One of `"none"`, `"output"`, or `"all"`; controls whether `$chat()`
#'   prints the completed text. The compatibility wrapper accepts `TRUE`,
#'   `FALSE`, and `"text"` as aliases for `"output"`, `"none"`, and
#'   `"output"`, respectively.
#' @return An object inheriting from ellmer's `Chat` class.
#' The returned object retains ellmer's public Chat methods, history,
#' callbacks, registered tools, asynchronous methods, and R6 cloning behavior.
#'
#' @section Conditions:
#' Invalid arguments signal `codex_chat_argument_error`. Missing or
#' incompatible ellmer installations signal `codex_ellmer_missing` or
#' `codex_ellmer_compatibility_error`. Authentication failures found before
#' the Chat is constructed retain their package condition classes. Transport
#' and protocol errors retain their specific Codex/ellmer condition classes;
#' compatibility-shape failures use `codex_ellmer_compatibility_error`.
#' @section Side effects:
#' Constructing a chat reads the current process credential or this package's
#' credential store and may refresh an expired stored credential. When `model`
#' is omitted, or when an effort is supplied, it also queries the authenticated
#' account catalog. It does not open a browser or generate a response.
#' @seealso
#'   [codex_login()], [codex_account()], [codex_models()], [codex_logout()],
#'   and [ellmer::chat_openai()]
#' @examplesIf interactive()
#' chat <- chat_codex(
#'   system_prompt = "Be concise."
#' )
#' chat$chat("Hello")
#'
#' weather_tool <- ellmer::tool(
#'   function(city) paste("Sunny in", city),
#'   name = "get_weather",
#'   description = "Get the current weather for a city.",
#'   arguments = list(city = ellmer::type_string())
#' )
#' chat$register_tool(weather_tool)
#' chat$chat("What is the weather in Montevideo?")
#' @export
chat_codex <- function(
  system_prompt = NULL,
  model = NULL,
  echo = c("none", "output", "all"),
  effort = NULL,
  params = NULL,
  api_args = list()
) {
  echo <- codex_echo(echo)
  invalid_system_prompt <- !is.null(system_prompt) &&
    (!is.character(system_prompt) || length(system_prompt) != 1L || is.na(system_prompt))
  if (invalid_system_prompt) {
    rlang::abort(
      "`system_prompt` must be NULL or one string.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  invalid_model <- !is.null(model) &&
    (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model))
  if (invalid_model) {
    rlang::abort(
      "`model` must be NULL or one non-empty string.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  if (!is.null(params) && !is.list(params)) {
    rlang::abort(
      "`params` must be NULL or a list created by `ellmer::params()`.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  if (!is.list(api_args) || (length(api_args) > 0L && is.null(names(api_args)))) {
    rlang::abort(
      "`api_args` must be a named list.",
      class = "codex_chat_argument_error",
      parent = NULL
    )
  }
  effort <- codex_chat_reasoning_effort(effort, params)
  if (!is.null(effort)) {
    params <- params %||% list()
    params$reasoning_effort <- effort
  }

  codex_ellmer_compatibility()
  auth <- codex_auth()
  model <- codex_select_model(auth = auth, model = model, effort = effort)$model

  chat <- codex_ellmer_chat_openai(
    system_prompt = system_prompt,
    model = model,
    auth = auth,
    params = params,
    api_args = api_args,
    echo = echo
  )
  codex_patch_chat(chat, default_echo = echo)
}

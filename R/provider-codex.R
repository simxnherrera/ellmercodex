# The installed ellmer 0.4.2 release is the compatibility source of truth.
# The public Chat object remains the external seam; the version-gated provider
# and private turn-submission implementation live in ellmer-compatibility.R.

#' Check the exported ellmer compatibility seam
#'
#' The package supports exactly the inspected ellmer 0.4.2 Chat
#' implementation. A later upstream release must be audited before it can be
#' admitted because the transport uses version-gated private ellmer seams.
#'
#' @return The installed ellmer version, invisibly.
#' @keywords internal
codex_ellmer_compatibility <- function() {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    rlang::abort(
      "`chat_codex()` requires the ellmer package.",
      class = c("codex_ellmer_missing", "codex_ellmer_compatibility_error"),
      parent = NULL
    )
  }

  version <- utils::packageVersion("ellmer")
  if (!identical(as.character(version), "0.4.2")) {
    rlang::abort(
      paste0(
        "`chat_codex()` supports exactly ellmer 0.4.2; installed ",
        "version is ", version, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  required <- c(
    "AssistantTurn", "AssistantPartialTurn", "ContentText",
    "ContentToolRequest", "ContentToolResult", "ContentImageInline",
    "ContentImageRemote", "ContentPDF", "ContentThinking", "UserTurn",
    "params", "tool", "stream_controller"
  )
  available <- vapply(
    required,
    function(name) name %in% getNamespaceExports("ellmer"),
    logical(1)
  )
  if (!all(available)) {
    missing <- paste(required[!available], collapse = ", ")
    rlang::abort(
      paste0("The installed ellmer version is missing exported symbols: ", missing, "."),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  required_internals <- c(
    "Chat", "TurnAccumulator", "chat_perform", "base_request", "chat_path",
    "modify_list", "chat_body", "as_user_turn", "chat_request",
    "stream_parse", "stream_content", "stream_merge_chunks", "value_turn",
    "value_tokens", "value_finish_reason", "has_batch_support", "tokens",
    "dollars", "get_token_cost", "ContentJson", "ContentToolRequestSearch",
    "type_needs_wrapper",
    "wrap_type_if_needed", "extract_data", "check_echo", "match_tools",
    "invoke_tools", "invoke_tools_async", "turn_has_tool_request",
    "tool_results_as_turn", "echo_non_text_contents", "emitter", "content_text",
    "cat_line", "otel_chat_input", "local_chat_otel_span",
    "record_chat_otel_span_status", "record_chat_otel_span_output",
    "local_agent_otel_span", "warn_tool_errors", "turn_get_tool_errors",
    "is_tool_request", "is_tool_result"
  )
  available_internals <- vapply(
    required_internals,
    function(name) exists(name, envir = asNamespace("ellmer"), inherits = FALSE),
    logical(1)
  )
  if (!all(available_internals)) {
    missing <- paste(required_internals[!available_internals], collapse = ", ")
    rlang::abort(
      paste0(
        "The installed ellmer 0.4.2 release is missing compatibility symbols: ",
        missing, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  invisible(version)
}

codex_ellmer_structured_compatibility <- function() {
  required <- c(
    "ContentJson",
    "extract_data",
    "type_needs_wrapper",
    "wrap_type_if_needed"
  )
  namespace <- asNamespace("ellmer")
  available <- vapply(
    required,
    function(name) exists(name, envir = namespace, inherits = FALSE),
    logical(1)
  )
  if (!all(available)) {
    missing <- paste(required[!available], collapse = ", ")
    rlang::abort(
      paste0(
        "The installed ellmer version is missing structured-output compatibility symbols: ",
        missing, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  invisible(TRUE)
}

codex_ellmer_chat_methods <- function(chat) {
  required <- c(
    "initialize", "get_turns", "set_turns", "add_turn", "get_system_prompt",
    "get_model", "set_model", "set_system_prompt", "get_tokens", "get_cost",
    "last_turn", "chat", "chat_structured", "chat_structured_async", "chat_async",
    "stream", "stream_async", "register_tool", "register_tools", "get_provider",
    "get_tools", "set_tools", "on_tool_request", "on_tool_result", "clone"
  )
  interface <- codex_ellmer_chat_interface()
  chat_class <- utils::getFromNamespace("Chat", "ellmer")
  installed_methods <- chat_class$public_methods
  available <- tryCatch(
    vapply(required, function(name) {
      method <- chat[[name]]
      is.function(method) &&
        is.function(installed_methods[[name]]) &&
        identical(
          formals(method),
          formals(installed_methods[[name]])
        ) &&
        identical(names(formals(method)) %||% character(), interface$formal_names[[name]])
    }, logical(1)),
    error = function(error) rep(FALSE, length(required))
  )
  if (!all(available)) {
    missing <- paste(required[!available], collapse = ", ")
    rlang::abort(
      paste0("The ellmer Chat object is missing public methods: ", missing, "."),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  public_names <- tryCatch(names(chat), error = function(error) character())
  unexpected <- setdiff(public_names, c(".__enclos_env__", required))
  if (length(unexpected) > 0L) {
    rlang::abort(
      paste0(
        "The installed ellmer Chat exposed unexpected public fields: ",
        paste(unexpected, collapse = ", "), "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  invisible(chat)
}

codex_ellmer_chat_openai <- function(
  system_prompt = NULL,
  model,
  auth,
  params = NULL,
  api_args = list(),
  echo = "none"
) {
  codex_ellmer_compatibility()
  echo <- codex_echo(echo)

  if (!inherits(auth, "codex_auth")) {
    rlang::abort(
      "The Codex authentication object is invalid.",
      class = "codex_chat_error",
      parent = NULL
    )
  }

  persist <- tryCatch(codex_session_persists(), error = function(error) FALSE)
  provider <- tryCatch(
    codex_new_provider(
      model = model,
      auth = auth,
      params = params,
      api_args = api_args,
      persist = persist
    ),
    error = function(error) {
      if (inherits(error, "codex_ellmer_compatibility_error")) stop(error)
      rlang::abort(
        "The Codex ellmer provider could not be constructed.",
        class = "codex_chat_error",
        parent = error
      )
    }
  )
  chat_class <- utils::getFromNamespace("Chat", "ellmer")
  chat <- tryCatch(
    chat_class$new(
      provider = provider,
      system_prompt = system_prompt,
      echo = echo
    ),
    error = function(error) {
      rlang::abort(
        "The Codex ellmer Chat could not be constructed.",
        class = "codex_chat_error",
        parent = error
      )
    }
  )

  if (!inherits(chat, "Chat")) {
    rlang::abort(
      "The installed ellmer factory did not return a Chat object.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  codex_ellmer_chat_methods(chat)
  codex_install_private_submit_methods(chat)
}

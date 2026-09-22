# ellmer 0.5.0 is the minimum supported interface.
# The public Chat object remains the external seam; the provider
# and private turn-submission implementation live in ellmer-compatibility.R.

#' Check the exported ellmer compatibility seam
#'
#' The package requires ellmer 0.5.0 or later and checks the private contracts
#' needed by the Codex streaming transport before constructing a chat.
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
  if (version < package_version("0.5.0")) {
    rlang::abort(
      paste0(
        "`chat_codex()` requires ellmer >= 0.5.0; installed version is ",
        version, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  required <- c(
    "AssistantTurn", "AssistantPartialTurn", "ContentText",
    "ContentToolRequest", "ContentToolResult", "ContentImageInline",
    "ContentImageRemote", "ContentPDF", "ContentThinking", "UserTurn",
    "params", "tool", "stream_controller", "Model"
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
    "Chat", "ProviderOpenAI", "TurnAccumulator", "chat_perform",
    "base_request", "chat_path", "modify_list", "chat_body", "chat_request",
    "stream_parse", "stream_content", "stream_merge_chunks", "value_turn",
    "value_tokens", "value_finish_reason", "has_batch_support",
    "dollars", "get_token_cost", "ContentJson", "ContentToolRequestSearch",
    "invoke_tools", "invoke_tools_async", "turn_has_tool_request",
    "tool_results_as_turn", "echo_non_text_contents", "emitter", "content_text",
    "cat_line", "otel_chat_input", "local_chat_otel_span",
    "record_chat_otel_span_status", "record_chat_otel_span_output",
    "local_agent_otel_span", "warn_tool_errors", "turn_get_tool_errors",
    "is_tool_request", "is_tool_result", "new_tool_context",
    "count_tokens", "file_upload", "file_list", "file_get",
    "file_download", "file_delete"
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
        "The installed ellmer release is missing compatibility symbols: ",
        missing, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  required_formals <- list(
    chat_body = c("provider", "model", "stream", "turns", "tools", "type"),
    chat_request = c("provider", "model", "stream", "turns", "tools", "type"),
    stream_content = c("provider", "event", "completion"),
    stream_parse = c("provider", "event"),
    stream_merge_chunks = c("provider", "result", "chunk"),
    value_turn = c("provider", "model", "result", "has_type"),
    value_tokens = c("provider", "json"),
    value_finish_reason = c("provider", "result"),
    chat_perform = c("provider", "model", "mode", "turns", "tools", "type",
                     "otel_span", "controller"),
    local_agent_otel_span = c("provider", "model", "activate"),
    local_chat_otel_span = c("provider", "model", "turns",
                             "system_prompt", "parent"),
    invoke_tools = c("turn", "echo", "on_tool_request",
                     "on_tool_result", "yield_request", "otel_span",
                     "tool_context"),
    invoke_tools_async = c("turn", "echo", "on_tool_request",
                           "on_tool_result", "yield_request", "otel_span",
                           "tool_context"),
    get_token_cost = c("provider_name", "model_name", "tokens", "variant")
  )
  for (name in names(required_formals)) {
    actual <- names(formals(get(name, envir = asNamespace("ellmer"))))
    if (!all(required_formals[[name]] %in% actual)) {
      rlang::abort(
        paste0("ellmer ", version, " changed the required `", name,
               "()` contract; expected arguments: ",
               paste(required_formals[[name]], collapse = ", "), "."),
        class = "codex_ellmer_compatibility_error",
        parent = NULL
      )
    }
  }
  accumulator <- utils::getFromNamespace("TurnAccumulator", "ellmer")
  accumulator_methods <- c("initialize", "begin_turn", "update_turn",
                           "complete_turn", "finalize_turn", "value_turn")
  if (!all(vapply(accumulator_methods, function(name) {
    is.function(accumulator$public_methods[[name]])
  }, logical(1))) ||
      !all(c("chat", "chat_private", "provider", "model", "controller",
             "turns", "turn_idx", "start_time") %in%
           names(accumulator$public_fields))) {
    rlang::abort(
      "ellmer changed the TurnAccumulator contract required by Codex.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  invisible(version)
}

codex_ellmer_chat_methods <- function(chat) {
  required <- c(
    "initialize", "get_turns", "set_turns", "add_turn", "get_system_prompt",
    "get_model", "get_model_object", "set_model", "set_system_prompt", "get_tokens", "get_cost",
    "last_turn", "chat", "chat_structured", "chat_structured_async", "chat_async",
    "stream", "stream_async", "register_tool", "register_tools", "get_provider",
    "get_tools", "set_tools", "on_tool_request", "on_tool_result",
    "on_request_start", "on_request_end", "clone"
  )
  available <- tryCatch(
    vapply(required, function(name) {
      is.function(chat[[name]])
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
  provider_config <- tryCatch(
    codex_new_provider(
      model = model,
      auth = auth,
      params = params,
      api_args = api_args,
      persist = persist
    ),
    error = function(error) {
      if (inherits(error, c("codex_ellmer_compatibility_error",
                            "codex_chat_error"))) stop(error)
      rlang::abort(
        "The installed ellmer Provider or Model constructor changed.",
        class = "codex_ellmer_compatibility_error",
        parent = error
      )
    }
  )
  chat_class <- utils::getFromNamespace("Chat", "ellmer")
  chat <- tryCatch(
    chat_class$new(
      provider = provider_config$provider,
      model = provider_config$model,
      system_prompt = system_prompt,
      echo = echo
    ),
    error = function(error) {
      rlang::abort(
        "The installed ellmer Chat constructor changed.",
        class = "codex_ellmer_compatibility_error",
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

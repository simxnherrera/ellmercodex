# The Codex chat deliberately uses ellmer's exported OpenAI factory rather
# than implementing an ellmer Provider subclass. In ellmer 0.4.2 the provider
# generics and Chat constructor are internal, and relying on them would make
# this package tightly coupled to an unstable implementation seam. Structured
# output and Codex Responses tool calling each use a small, separately-gated
# compatibility fallback; ordinary text chat remains on exported methods.

#' Check the exported ellmer compatibility seam
#'
#' The package currently supports the public `ellmer` 0.4.x API starting at
#' 0.4.2. This check is intentionally kept in one helper so a later upstream
#' API change can be handled by one compatibility update and one offline test.
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
  if (version < numeric_version("0.4.2") ||
        version >= numeric_version("0.5.0")) {
    rlang::abort(
      paste0(
        "`chat_codex()` supports ellmer >= 0.4.2 and < 0.5.0; installed ",
        "version is ", version, "."
      ),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  required <- c(
    "chat_openai", "AssistantTurn", "ContentText", "ContentToolRequest",
    "ContentToolResult", "UserTurn", "params", "tool"
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
    "stream", "chat_structured", "get_turns", "set_turns", "get_tools",
    "register_tool", "register_tools", "on_tool_request", "on_tool_result"
  )
  available <- tryCatch(
    vapply(required, function(name) is.function(chat[[name]]), logical(1)),
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
  api_args = list()
) {
  codex_ellmer_compatibility()

  if (!inherits(auth, "codex_auth")) {
    rlang::abort(
      "The Codex authentication object is invalid.",
      class = "codex_chat_error",
      parent = NULL
    )
  }

  chat <- tryCatch(
    ellmer::chat_openai(
      system_prompt = system_prompt,
      base_url = sub("/responses$", "", codex_responses_url()),
      # Capture the already validated/refreshable auth supplied by
      # `chat_codex()`. Calling `codex_auth()` here would make ellmer's
      # construction-time credential probe consult the user's keyring again,
      # and would make fixture-authenticated chats non-deterministic.
      credentials = function() auth$access_token,
      model = model,
      params = params,
      api_args = api_args,
      api_headers = c(
        `ChatGPT-Account-Id` = auth$account_id,
        originator = codex_originator(),
        `OpenAI-Beta` = codex_protocol_version(),
        Accept = "text/event-stream"
      ),
      service_tier = "default",
      echo = "none"
    ),
    error = function(error) {
      rlang::abort(
        "The Codex ellmer chat could not be constructed.",
        class = "codex_chat_error",
        parent = NULL
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
  chat
}

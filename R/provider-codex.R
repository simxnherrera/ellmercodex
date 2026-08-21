# The Codex chat deliberately uses ellmer's exported OpenAI factory rather
# than implementing an ellmer Provider subclass. In ellmer 0.4.2 the provider
# generics and Chat constructor are internal, and relying on them would make
# this package tightly coupled to an unstable implementation seam.

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

  required <- c("chat_openai", "AssistantTurn", "ContentText")
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

codex_ellmer_chat_methods <- function(chat) {
  required <- c("stream", "get_turns", "set_turns")
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
  auth
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
      credentials = function() codex_auth()$access_token,
      model = model,
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

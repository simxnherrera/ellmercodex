# Account-specific model discovery is intentionally conservative.

codex_models_unsupported_reason <- function() {
  paste(
    "Account-specific Codex model discovery is not supported by the current",
    "documented interface. No model catalog is bundled or inferred; select a",
    "model explicitly with the `model` argument to `chat_codex()` instead."
  )
}

codex_models_result <- function(models = data.frame()) {
  class(models) <- unique(c("codex_models_unsupported", "codex_models", class(models)))
  attr(models, "supported") <- FALSE
  attr(models, "reason") <- codex_models_unsupported_reason()
  models
}

#' Report whether account-specific Codex model discovery is available.
#'
#' The current subscription compatibility transport does not expose a
#' documented, reliable model-list endpoint. This function therefore returns a
#' typed empty result rather than inventing a catalog from another client or
#' account.
#'
#' @return An empty data frame with class `codex_models_unsupported` and a
#'   `reason` attribute explaining the limitation. The `supported` attribute is
#'   `FALSE`.
#' @examples
#' models <- codex_models()
#' attr(models, "supported")
#' attr(models, "reason")
#' @export
codex_models <- function() {
  codex_models_result(data.frame(
    id = character(),
    owned_by = character(),
    stringsAsFactors = FALSE
  ))
}

#' @export
print.codex_models_unsupported <- function(x, ...) {
  reason <- attr(x, "reason") %||% codex_models_unsupported_reason()
  cat("No Codex model catalog available. ", reason, "\n", sep = "")
  invisible(x)
}

# Internal condition helpers used by the authentication and credential layer.

codex_auth_abort <- function(message, class = "codex_auth_error", parent = NULL) {
  classes <- unique(c(class, "codex_auth_error"))
  rlang::abort(message, class = classes, parent = parent)
}

codex_auth_scalar_character <- function(value, allow_empty = FALSE) {
  ok <- is.character(value) && length(value) == 1L && !is.na(value)
  if (!ok) {
    return(FALSE)
  }
  allow_empty || nzchar(value)
}

codex_auth_require_string <- function(value, name, allow_empty = FALSE) {
  if (!codex_auth_scalar_character(value, allow_empty = allow_empty)) {
    codex_auth_abort(
      sprintf("`%s` must be one %s string.", name, if (allow_empty) "character" else "non-empty character"),
      class = "codex_auth_argument_error"
    )
  }
  invisible(value)
}

codex_auth_error_message <- function(operation, include_retry = FALSE) {
  suffix <- if (isTRUE(include_retry)) " Run codex_login() if the problem persists." else ""
  paste0("Codex OAuth ", operation, " failed.", suffix)
}

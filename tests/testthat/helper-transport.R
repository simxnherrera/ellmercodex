fake_codex_auth <- function() {
  structure(
    list(
      access_token = "fixture-access-token",
      refresh_token = "fixture-refresh-token",
      account_id = "fixture-account-id",
      expires_at = as.numeric(Sys.time()) + 3600
    ),
    class = c("codex_auth", "list")
  )
}

fixture_text <- function(name) {
  path <- testthat::test_path("fixtures", name)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_file <- if (length(script_arg) > 0L) {
  sub("^--file=", "", script_arg[[1L]])
} else {
  file.path(getwd(), "poc", "validate-offline.R")
}
source(file.path(dirname(normalizePath(script_file, mustWork = TRUE)), "run.R"))
rm(script_arg, script_file)

assert <- function(ok, label) {
  if (!isTRUE(ok)) stop("Offline validation failed: ", label, call. = FALSE)
  cat("ok - ", label, "\n", sep = "")
}

pkce <- codex_pkce()
assert(grepl("^[A-Za-z0-9._~-]{43,128}$", pkce$verifier), "PKCE verifier format")
assert(
  identical(pkce$challenge, codex_base64url_encode(openssl::sha256(charToRaw(pkce$verifier)))),
  "PKCE S256 challenge"
)

state <- codex_oauth_state()
assert(codex_validate_state(state, state), "OAuth state accepts exact match")
assert(!codex_validate_state(state, paste0(state, "x")), "OAuth state rejects mismatch")

authorize_query <- httr2::url_parse(codex_authorize_url(pkce, state))$query
assert(identical(authorize_query$redirect_uri, codex_redirect_uri()), "registered redirect URI")
assert(identical(authorize_query$originator, "ellmercodex"), "honest OAuth originator")
assert(identical(authorize_query$state, state), "OAuth state included in request")

callback_success <- codex_callback_result(
  codex_parse_query("?code=fixture-code&state=fixture-state"),
  "fixture-state"
)
assert(
  identical(callback_success$code, "fixture-code") && is.null(callback_success$error),
  "OAuth callback parser accepts code and matching state"
)
callback_failure <- codex_callback_result(
  codex_parse_query("error=access_denied&state=fixture-state"),
  "fixture-state"
)
assert(
  grepl("access_denied", callback_failure$error, fixed = TRUE),
  "OAuth callback parser reports a safe error code"
)

fake_claims <- codex_base64url_encode(charToRaw('{"exp":2000}'))
fake_jwt <- paste("e30", fake_claims, "signature", sep = ".")
fake_auth <- structure(
  list(
    access_token = fake_jwt,
    refresh_token = "test-refresh-not-a-secret",
    id_token = NULL,
    account_id = "test-account",
    expires_at = 2000
  ),
  class = c("codex_auth", "list")
)
assert(!codex_token_expired(fake_auth, skew = 0, now = 1999), "expiration before deadline")
assert(codex_token_expired(fake_auth, skew = 0, now = 2000), "expiration at deadline")
assert(codex_token_expired(fake_auth, skew = 60, now = 1940), "refresh skew decision")

headers <- codex_request_headers(fake_auth)
assert(identical(unname(headers[["originator"]]), "ellmercodex"), "honest request originator")
body <- codex_request_body("test")
assert(identical(body$stream, TRUE) && identical(body$store, FALSE), "streaming, non-stored body")

redacted <- codex_redact(
  paste(
    "Authorization: Bearer abc.def.ghi?code=secret&state=secret",
    "access_token=secret ChatGPT-Account-Id: secret"
  )
)
assert(!grepl("secret|abc.def.ghi", redacted, fixed = FALSE), "credential redaction")

fixture <- list(output = list(list(
  type = "message",
  content = list(list(type = "output_text", text = "Hello from R"))
)))
assert(identical(codex_parse_response(fixture), "Hello from R"), "response parsing")

sse_fixture <- paste0(
  "event: response.output_text.delta\r\n",
  'data: {"type":"response.output_text.delta","delta":"Hello "}\r\n\r\n',
  'data: {"type":"response.output_text.delta","delta":"from R"}\r\n\r\n',
  'data: {"type":"response.completed","response":{"status":"completed"}}\r\n\r\n',
  "data: [DONE]\r\n\r\n"
)
sse_events <- codex_parse_sse(sse_fixture)
assert(identical(length(sse_events), 3L), "SSE framing and JSON parsing")
assert(
  identical(codex_parse_sse_response(sse_events), "Hello from R"),
  "buffered SSE text assembly"
)
assert(codex_is_sse_body(NA_character_, sse_fixture), "SSE sniffing without content type")
assert(!codex_is_sse_body("application/json", '{"output":[]}'), "JSON is not misclassified as SSE")

sse_failure <- tryCatch(
  codex_parse_sse_response(list(list(
    type = "response.failed",
    response = list(error = list(message = "fixture failure"))
  ))),
  error = function(error) error
)
assert(inherits(sse_failure, "codex_generation_error"), "SSE failure condition")

sse_incomplete <- tryCatch(
  codex_parse_sse_response(list(list(
    type = "response.incomplete",
    response = list(status = "incomplete")
  ))),
  error = function(error) error
)
assert(inherits(sse_incomplete, "codex_incomplete_error"), "SSE incomplete condition")
assert(
  identical(
    codex_error_detail_value(list(detail = "Stream must be set to true")),
    "Stream must be set to true"
  ),
  "top-level error detail parsing"
)

fixture_chat_class <- R6::R6Class(
  "CodexFixtureChat",
  lock_objects = TRUE,
  private = list(turns = list()),
  public = list(
    chat = function(...) stop("unpatched fixture chat", call. = FALSE),
    stream = function(..., stream = "text", controller = NULL) {
      private$turns <- c(
        private$turns,
        list(
          ellmer::UserTurn(list(ellmer::ContentText("fixture prompt"))),
          ellmer::AssistantTurn()
        )
      )
      coro::generator(function() {
        coro::yield("Hello ")
        coro::yield("from R")
      })()
    },
    get_turns = function() private$turns,
    set_turns = function(turns) private$turns <- turns
  )
)
fixture_chat <- fixture_chat_class$new()
class(fixture_chat) <- c("Chat", class(fixture_chat))
fixture_chat <- codex_patch_chat(fixture_chat)

fixture_value <- fixture_chat$chat("ignored")
assert(
  inherits(fixture_value, "ellmer_output") && identical(as.character(fixture_value), "Hello from R"),
  "chat_codex compatibility returns ellmer output"
)
fixture_turns <- fixture_chat$get_turns()
assert(
  identical(fixture_turns[[2L]]@contents[[1L]]@text, "Hello from R"),
  "chat_codex compatibility repairs assistant history"
)

fixture_stream <- fixture_chat$stream("ignored")
fixture_chunks <- coro::collect(fixture_stream)
assert(
  identical(paste0(fixture_chunks, collapse = ""), "Hello from R") &&
    identical(fixture_chat$get_turns()[[4L]]@contents[[1L]]@text, "Hello from R"),
  "chat_codex compatibility preserves streamed history"
)

config_functions <- c(
  "codex_oauth_client_id", "codex_authorization_url", "codex_token_url",
  "codex_responses_url", "codex_protocol_version", "codex_request_headers"
)
assert(all(vapply(config_functions, exists, logical(1), mode = "function")), "configuration centralization")

rm(
  fixture_chat_class, fixture_chat, fixture_value, fixture_turns,
  fixture_stream, fixture_chunks
)

cat("All offline validations passed. No network or credential access was attempted.\n")

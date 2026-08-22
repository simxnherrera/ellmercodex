#!/usr/bin/env Rscript

# Full ellmercodex verification runner.
#
# Default behavior is offline: it runs tests/testthat with its fixture-backed
# HTTP/SSE responses and never opens a browser, inspects the credential store,
# or sends a request. Set ELLMERCODEX_RUN_LIVE_TESTS=true to add the opt-in
# live checks.

truthy <- function(value) {
  tolower(trimws(value)) %in% c("1", "true", "yes", "on")
}

script_path <- tryCatch({
  argument <- grep("^--file=", commandArgs(), value = TRUE)
  if (length(argument) == 0L) "" else sub("^--file=", "", argument[[1L]])
}, error = function(error) "")

find_project_root <- function() {
  starts <- unique(c(
    if (nzchar(script_path)) dirname(normalizePath(script_path, mustWork = FALSE)),
    getwd()
  ))

  for (start in starts) {
    directory <- normalizePath(start, mustWork = FALSE)
    for (i in seq_len(8L)) {
      if (file.exists(file.path(directory, "DESCRIPTION")) &&
          dir.exists(file.path(directory, "tests", "testthat"))) {
        return(directory)
      }
      parent <- dirname(directory)
      if (identical(parent, directory)) break
      directory <- parent
    }
  }

  stop(
    "Could not find the ellmercodex project root. Run this script from the repository or keep it under inst/manual-tests/.",
    call. = FALSE
  )
}

project_root <- find_project_root()
test_dir <- file.path(project_root, "tests", "testthat")

missing <- c("jsonlite", "pkgload", "testthat")
missing <- missing[!vapply(missing, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0L) {
  stop(
    "The runner needs these installed packages: ",
    paste(missing, collapse = ", "),
    call. = FALSE
  )
}

output_root <- Sys.getenv(
  "ELLMERCODEX_TEST_OUTPUT",
  unset = file.path(project_root, "ellmercodex-test-results")
)
run_id <- paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", Sys.getpid())
run_dir <- file.path(output_root, run_id)
if (!dir.create(run_dir, recursive = TRUE, showWarnings = FALSE) &&
    !dir.exists(run_dir)) {
  stop("Could not create output directory: ", run_dir, call. = FALSE)
}

artifact <- function(name) file.path(run_dir, name)

write_json <- function(value, path) {
  jsonlite::write_json(
    value,
    path,
    dataframe = "rows",
    POSIXt = "ISO8601",
    na = "null",
    pretty = TRUE,
    auto_unbox = TRUE,
    null = "null"
  )
}

write_json_or_error <- function(value, path) {
  tryCatch(write_json(value, path), error = function(error) {
    writeLines(
      c(
        "JSON serialization failed:",
        conditionMessage(error)
      ),
      sub("\\.json$", ".error.txt", path)
    )
    stop(error)
  })
}

write_error <- function(error, path) {
  writeLines(
    c(
      paste("class:", paste(class(error), collapse = ", ")),
      paste("message:", conditionMessage(error))
    ),
    path,
    useBytes = TRUE
  )
}

runner_or <- function(x, y) if (is.null(x)) y else x

as_scalar <- function(value, default = NA_character_) {
  if (length(value) == 1L && !is.na(value)) as.character(value) else default
}

test_status <- function(test) {
  classes <- unlist(lapply(test$results, class), use.names = FALSE)
  if (any(grepl("expectation_(failure|error|broken)", classes))) {
    return("fail")
  }
  if (any(grepl("expectation_skip", classes))) return("skip")
  "pass"
}

test_warning_count <- function(test) {
  classes <- unlist(lapply(test$results, class), use.names = FALSE)
  sum(grepl("expectation_warning", classes))
}

xml_escape <- function(value) {
  value <- as.character(value)
  value <- gsub("&", "&amp;", value, fixed = TRUE)
  value <- gsub("<", "&lt;", value, fixed = TRUE)
  value <- gsub(">", "&gt;", value, fixed = TRUE)
  value <- gsub('"', "&quot;", value, fixed = TRUE)
  gsub("'", "&apos;", value, fixed = TRUE)
}

write_junit_xml <- function(rows, path, suite_error = NULL) {
  failures <- sum(rows$status == "fail")
  skipped <- sum(rows$status == "skip")
  total_time <- sum(rows$real_seconds, na.rm = TRUE)
  lines <- c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    sprintf(
      '<testsuite name="ellmercodex" tests="%d" failures="%d" skipped="%d" time="%.6f">',
      nrow(rows), failures, skipped, total_time
    )
  )

  if (nrow(rows) > 0L) {
    for (i in seq_len(nrow(rows))) {
      row <- rows[i, , drop = FALSE]
      name <- xml_escape(row$test[[1L]])
      class <- xml_escape(paste(row$file[[1L]], row$context[[1L]], sep = "::"))
      time <- if (is.finite(row$real_seconds[[1L]])) row$real_seconds[[1L]] else 0
      lines <- c(
        lines,
        sprintf(
          '  <testcase classname="%s" name="%s" time="%.6f">',
          class,
          name,
          time
        )
      )
      if (identical(row$status[[1L]], "fail")) {
        lines <- c(lines, '    <failure message="testthat expectation failed"/>')
      } else if (identical(row$status[[1L]], "skip")) {
        lines <- c(lines, '    <skipped/>')
      }
      lines <- c(lines, "  </testcase>")
    }
  }

  if (!is.null(suite_error)) {
    lines <- c(
      lines,
      sprintf(
        '  <system-err>%s</system-err>',
        xml_escape(conditionMessage(suite_error))
      )
    )
  }
  writeLines(c(lines, "</testsuite>"), path, useBytes = TRUE)
}

test_row <- function(test) {
  data.frame(
    file = as_scalar(test$file, ""),
    context = as_scalar(test$context, ""),
    test = as_scalar(test$test, ""),
    status = test_status(test),
    warnings = test_warning_count(test),
    expectations = length(test$results),
    user_seconds = as.numeric(runner_or(test$user, NA_real_)),
    system_seconds = as.numeric(runner_or(test$system, NA_real_)),
    real_seconds = as.numeric(runner_or(test$real, NA_real_)),
    stringsAsFactors = FALSE
  )
}

save_turn_artifacts <- function(chat, prefix) {
  turns <- chat$get_turns(include_system_prompt = TRUE)
  saveRDS(turns, artifact(paste0(prefix, "-turns.rds")))
  writeLines(
    capture.output(str(turns, max.level = 3L)),
    artifact(paste0(prefix, "-turns.txt")),
    useBytes = TRUE
  )
  invisible(turns)
}

assistant_history <- function(turns) {
  Filter(function(turn) identical(turn@role, "assistant"), turns)
}

runner_await_promise <- function(promise, timeout = 120) {
  if (!requireNamespace("later", quietly = TRUE)) {
    stop("The live async check needs the later package.", call. = FALSE)
  }

  state <- new.env(parent = emptyenv())
  state$done <- FALSE
  state$value <- NULL
  state$error <- NULL

  promises::then(
    promise,
    function(value) {
      state$value <- value
      state$done <- TRUE
      invisible(value)
    },
    function(error) {
      state$error <- error
      state$done <- TRUE
      invisible(NULL)
    }
  )

  started <- Sys.time()
  while (!isTRUE(state$done)) {
    later::run_now(0.05)
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) >= timeout) {
      stop("The live async promise did not settle before the timeout.", call. = FALSE)
    }
  }
  if (!is.null(state$error)) stop(state$error)
  state$value
}

collapse_stream_text <- function(chunks) {
  if (is.character(chunks)) return(paste0(chunks, collapse = ""))
  paste0(
    vapply(
      chunks,
      function(chunk) {
        if (is.character(chunk)) return(paste0(chunk, collapse = ""))
        if (inherits(chunk, "ellmer::ContentText")) return(chunk@text)
        ""
      },
      character(1)
    ),
    collapse = ""
  )
}

require_nonempty_text <- function(value, label) {
  text <- paste0(as.character(value), collapse = "")
  if (!nzchar(trimws(text))) {
    stop(label, " returned empty text.", call. = FALSE)
  }
  text
}

assert_exact_text <- function(value, expected, label) {
  actual <- trimws(paste0(as.character(value), collapse = ""))
  expected <- trimws(expected)
  if (!identical(actual, expected)) {
    stop(
      label,
      " returned unexpected text. Expected `",
      expected,
      "`; received `",
      actual,
      "`.",
      call. = FALSE
    )
  }
  invisible(actual)
}

with_env_unset <- function(name, code) {
  previous <- Sys.getenv(name, unset = NA_character_)
  on.exit({
    if (is.na(previous)) {
      Sys.unsetenv(name)
    } else {
      do.call(Sys.setenv, setNames(list(previous), name))
    }
  }, add = TRUE)
  Sys.unsetenv(name)
  force(code)
}

catalog_model_row <- function(models, model) {
  index <- match(model, models$id)
  if (is.na(index)) {
    stop(
      "The selected live model was not returned by codex_models(): ",
      model,
      call. = FALSE
    )
  }
  models[index, , drop = FALSE]
}

catalog_model_effort <- function(models, model) {
  row <- catalog_model_row(models, model)
  supported <- row$supported_reasoning_efforts[[1L]]
  default <- row$default_reasoning_effort[[1L]]
  if (!is.character(supported)) supported <- character()
  if (is.character(default) && length(default) == 1L &&
      !is.na(default) && nzchar(default) && default %in% supported) {
    return(default)
  }
  if (is.character(supported) && length(supported) > 0L) {
    return(supported[[1L]])
  }
  stop(
    "The selected live model did not advertise a reasoning effort.",
    call. = FALSE
  )
}

write_model_artifacts <- function(models) {
  saveRDS(models, artifact("live-models.rds"))
  effort <- vapply(
    models$supported_reasoning_efforts,
    function(value) paste(value, collapse = ","),
    character(1)
  )
  tiers <- vapply(
    models$service_tiers,
    function(value) paste(value, collapse = ","),
    character(1)
  )
  table <- data.frame(
    id = models$id,
    owned_by = models$owned_by,
    display_name = models$display_name,
    default_reasoning_effort = models$default_reasoning_effort,
    supported_reasoning_efforts = effort,
    supported_in_api = models$supported_in_api,
    priority = models$priority,
    default_service_tier = models$default_service_tier,
    service_tiers = tiers,
    stringsAsFactors = FALSE
  )
  utils::write.csv(table, artifact("live-models.csv"), row.names = FALSE)
  invisible(table)
}

run_live_checks <- function() {
  enabled <- truthy(Sys.getenv("ELLMERCODEX_RUN_LIVE_TESTS", unset = "false"))
  status <- list(
    enabled = enabled,
    status = if (enabled) "not_run" else "skipped",
    passed = if (enabled) FALSE else NULL,
    login = NULL,
    model_catalog = NULL,
    model = NULL,
    default_model = NULL,
    reasoning_effort = NULL,
    error = NULL
  )
  if (!enabled) {
    write_json(status, artifact("live-status.json"))
    return(status)
  }

  tryCatch({
    if (!isTRUE(ellmercodex::codex_available())) {
      stop("codex_available() returned FALSE.", call. = FALSE)
    }

    force_login <- truthy(Sys.getenv("ELLMERCODEX_LIVE_EXPLICIT_LOGIN", unset = "false"))
    auth <- NULL
    auth_error <- NULL
    if (!force_login) {
      auth <- tryCatch(
        getFromNamespace("codex_auth", "ellmercodex")(),
        error = function(error) {
          auth_error <<- error
          NULL
        }
      )
      if (is.null(auth) && !is.null(auth_error) &&
          !inherits(auth_error, "codex_auth_missing")) {
        stop(auth_error)
      }
    }
    if (force_login || is.null(auth)) {
      timeout <- as.numeric(Sys.getenv("ELLMERCODEX_LOGIN_TIMEOUT", unset = "300"))
      auth <- ellmercodex::codex_login(persist = FALSE, timeout = timeout)
      status$login <- list(mode = "explicit", performed = TRUE, persisted = FALSE)
    } else {
      status$login <- list(mode = "stored-session", performed = FALSE, persisted = NULL)
    }
    account <- ellmercodex::codex_account(auth)
    write_json(account, artifact("live-account-redacted.json"))

    models <- ellmercodex::codex_models(auth = auth)
    write_model_artifacts(models)

    configured_model <- Sys.getenv("ELLMERCODEX_MODEL", unset = "")
    catalog_count <- length(models$id)
    status$model_catalog <- list(
      status = if (catalog_count > 0L) "passed" else "empty",
      count = catalog_count,
      configured_model = if (nzchar(configured_model)) configured_model else NULL
    )
    if (catalog_count == 0L) {
      stop(
        "codex_models() returned no selectable models; the live acceptance requires non-empty discovery.",
        call. = FALSE
      )
    }

    model <- configured_model
    if (!nzchar(model)) {
      usable <- which(!is.na(models$supported_in_api) & models$supported_in_api)
      if (length(usable) == 0L) {
        stop("The live catalog contained no usable models.", call. = FALSE)
      }
      model <- models$id[[usable[[1L]]]]
    }
    selected_row <- catalog_model_row(models, model)
    if (!isTRUE(selected_row$supported_in_api[[1L]])) {
      stop("The configured live model is not marked usable by the account catalog.", call. = FALSE)
    }
    effort <- catalog_model_effort(models, model)
    status$model <- model
    status$reasoning_effort <- effort

    default_chat <- with_env_unset(
      "ELLMERCODEX_MODEL",
      ellmercodex::chat_codex(echo = "none")
    )
    default_model <- default_chat$get_model()
    if (!default_model %in% models$id) {
      stop("chat_codex(model = NULL) selected a model absent from the live catalog.", call. = FALSE)
    }
    status$default_model <- default_model
    default_value <- default_chat$chat("Reply with exactly: live default ok")
    default_text <- require_nonempty_text(default_value, "default model chat")
    assert_exact_text(default_text, "live default ok", "default model chat")
    save_turn_artifacts(default_chat, "live-default-model")

    ordinary <- ellmercodex::chat_codex(
      model = model,
      system_prompt = "Reply briefly and follow exact-output requests.",
      effort = effort,
      echo = "none"
    )
    if (!identical(ordinary$get_provider()@params$reasoning_effort, effort)) {
      stop("The live reasoning effort was not installed in ellmer parameters.", call. = FALSE)
    }
    ordinary_value <- ordinary$chat("Reply with exactly: live chat ok")
    ordinary_text <- require_nonempty_text(ordinary_value, "chat")
    writeLines(
      ordinary_text,
      artifact("live-chat.txt"),
      useBytes = TRUE
    )
    ordinary_turns <- save_turn_artifacts(ordinary, "live-chat")
    assert_exact_text(ordinary_text, "live chat ok", "chat")
    assert_exact_text(
      ordinary_turns[[length(ordinary_turns)]]@text,
      "live chat ok",
      "chat history"
    )

    multi_turn <- ellmercodex::chat_codex(
      model = model,
      effort = effort,
      echo = "none"
    )
    first_multi <- multi_turn$chat(
      "Remember that the live codeword is amber. Reply exactly: live multi first"
    )
    second_multi <- multi_turn$chat(
      "What is the live codeword? Reply with only: amber"
    )
    first_multi <- require_nonempty_text(first_multi, "multi-turn first")
    second_multi <- require_nonempty_text(second_multi, "multi-turn second")
    assert_exact_text(first_multi, "live multi first", "multi-turn first")
    assert_exact_text(second_multi, "amber", "multi-turn second")
    multi_turns <- save_turn_artifacts(multi_turn, "live-multi-turn")
    multi_assistant_turns <- assistant_history(multi_turns)
    if (length(multi_assistant_turns) != 2L) {
      stop("The live multi-turn history did not contain exactly two assistant turns.", call. = FALSE)
    }
    assert_exact_text(
      multi_assistant_turns[[1L]]@text,
      "live multi first",
      "multi-turn first history"
    )
    assert_exact_text(
      multi_assistant_turns[[2L]]@text,
      "amber",
      "multi-turn second history"
    )

    streamed <- ellmercodex::chat_codex(model = model, echo = "none")
    stream_chunks <- coro::collect(
      streamed$stream("Reply with exactly: live stream ok", stream = "text")
    )
    stream_text <- require_nonempty_text(collapse_stream_text(stream_chunks), "stream")
    writeLines(
      stream_text,
      artifact("live-stream.txt"),
      useBytes = TRUE
    )
    stream_turns <- save_turn_artifacts(streamed, "live-stream")
    assert_exact_text(stream_text, "live stream ok", "stream")
    assert_exact_text(
      stream_turns[[length(stream_turns)]]@text,
      "live stream ok",
      "stream history"
    )

    structured <- ellmercodex::chat_codex(model = model, echo = "none")
    structured_value <- structured$chat_structured(
      "Return an object with name equal to Ada and age equal to 13.",
      type = ellmer::type_object(
        name = ellmer::type_string(),
        age = ellmer::type_integer()
      )
    )
    write_json_or_error(structured_value, artifact("live-structured.json"))
    structured_turns <- save_turn_artifacts(structured, "live-structured")
    if (length(structured_turns[[length(structured_turns)]]@contents) != 1L) {
      stop("structured history contained duplicate content items.", call. = FALSE)
    }

    async_chat <- ellmercodex::chat_codex(model = model, echo = "none")
    async_value <- runner_await_promise(async_chat$chat_async(
      "Reply with exactly: live async ok"
    ))
    async_text <- require_nonempty_text(async_value, "chat_async")
    writeLines(
      async_text,
      artifact("live-chat-async.txt"),
      useBytes = TRUE
    )
    async_turns <- save_turn_artifacts(async_chat, "live-chat-async")
    assert_exact_text(async_text, "live async ok", "chat_async")
    assert_exact_text(
      async_turns[[length(async_turns)]]@text,
      "live async ok",
      "chat_async history"
    )

    async_stream <- ellmercodex::chat_codex(model = model, echo = "none")
    async_chunks <- runner_await_promise(coro::async_collect(async_stream$stream_async(
      "Reply with exactly: live async stream ok",
      stream = "text"
    )))
    async_stream_text <- require_nonempty_text(
      collapse_stream_text(async_chunks),
      "stream_async"
    )
    writeLines(
      async_stream_text,
      artifact("live-stream-async.txt"),
      useBytes = TRUE
    )
    async_stream_turns <- save_turn_artifacts(async_stream, "live-stream-async")
    assert_exact_text(async_stream_text, "live async stream ok", "stream_async")
    assert_exact_text(
      async_stream_turns[[length(async_stream_turns)]]@text,
      "live async stream ok",
      "stream_async history"
    )

    structured_async <- ellmercodex::chat_codex(model = model, echo = "none")
    structured_async_value <- runner_await_promise(
      structured_async$chat_structured_async(
        "Return an object with name equal to Grace and age equal to 17.",
        type = ellmer::type_object(
          name = ellmer::type_string(),
          age = ellmer::type_integer()
        )
      )
    )
    write_json_or_error(
      structured_async_value,
      artifact("live-structured-async.json")
    )
    structured_async_turns <- save_turn_artifacts(
      structured_async,
      "live-structured-async"
    )
    if (!identical(as.character(structured_async_value$name), "Grace") ||
        !identical(as.integer(structured_async_value$age), 17L) ||
        length(structured_async_turns[[length(structured_async_turns)]]@contents) != 1L) {
      stop("structured async returned an unexpected value or duplicate history.", call. = FALSE)
    }

    clone_source <- ellmercodex::chat_codex(model = model, echo = "none")
    clone_source_value <- clone_source$chat("Reply with exactly: live clone source")
    clone <- clone_source$clone()
    clone_value <- clone$chat("Reply with exactly: live clone response")
    assert_exact_text(clone_source_value, "live clone source", "clone source")
    assert_exact_text(clone_value, "live clone response", "clone response")
    clone_source_turns <- save_turn_artifacts(clone_source, "live-clone-source")
    clone_turns <- save_turn_artifacts(clone, "live-clone")
    assert_exact_text(
      clone_source$last_turn()@text,
      "live clone source",
      "clone source history"
    )
    assert_exact_text(
      clone$last_turn()@text,
      "live clone response",
      "clone history"
    )
    if (length(clone_turns) <= length(clone_source_turns)) {
      stop("The live clone did not retain an independent continuation history.", call. = FALSE)
    }

    content_stream <- ellmercodex::chat_codex(model = model, echo = "none")
    content_chunks <- coro::collect(content_stream$stream(
      "Reply with exactly: live content stream ok",
      stream = "content"
    ))
    content_text <- require_nonempty_text(
      collapse_stream_text(content_chunks),
      "stream(content)"
    )
    writeLines(content_text, artifact("live-content-stream.txt"), useBytes = TRUE)
    writeLines(
      vapply(content_chunks, function(value) paste(class(value), collapse = "/"), character(1)),
      artifact("live-content-stream-chunks.txt"),
      useBytes = TRUE
    )
    content_turns <- save_turn_artifacts(content_stream, "live-content-stream")
    assert_exact_text(content_text, "live content stream ok", "stream(content)")
    if (any(vapply(content_chunks, inherits, logical(1), what = "ellmer::ContentJson")) ||
        !identical(
          content_turns[[length(content_turns)]]@text,
          "live content stream ok"
        )) {
      stop("content streaming returned duplicate or unexpected assistant content.", call. = FALSE)
    }

    tool_chat <- ellmercodex::chat_codex(model = model, echo = "none")
    tool_requests <- character()
    tool_results <- character()
    tool <- ellmer::tool(
      function(city) paste("Sunny in", city),
      name = "get_weather",
      description = "Get the weather for a city.",
      arguments = list(city = ellmer::type_string())
    )
    tool_chat$register_tool(tool)
    tool_chat$on_tool_request(function(request) {
      tool_requests <<- c(tool_requests, request@name)
    })
    tool_chat$on_tool_result(function(result) {
      tool_results <<- c(tool_results, "completed")
    })
    tool_value <- tool_chat$chat(
      paste(
        "You must call get_weather with city Montevideo.",
        "After receiving the tool result, reply exactly: live tool ok."
      )
    )
    tool_text <- require_nonempty_text(tool_value, "tool chat")
    writeLines(tool_text, artifact("live-tool-chat.txt"), useBytes = TRUE)
    write_json(
      list(requests = tool_requests, results = tool_results),
      artifact("live-tool-callbacks.json")
    )
    tool_turns <- save_turn_artifacts(tool_chat, "live-tool-chat")
    assert_exact_text(tool_text, "live tool ok.", "tool chat")
    if (length(tool_requests) != 1L || length(tool_results) != 1L ||
        length(tool_turns[[length(tool_turns)]]@contents) != 1L) {
      stop("tool chat did not complete one request/result round cleanly.", call. = FALSE)
    }

    png_path <- artifact("live-input.png")
    grDevices::png(png_path, width = 128, height = 128)
    graphics::par(mar = c(0, 0, 0, 0))
    graphics::plot.new()
    graphics::rect(0, 0, 1, 1, col = "steelblue", border = NA)
    graphics::text(0.5, 0.5, "OK", col = "white")
    grDevices::dev.off()
    pdf_path <- artifact("live-input.pdf")
    grDevices::pdf(pdf_path, width = 4, height = 4)
    graphics::par(mar = c(0, 0, 0, 0))
    graphics::plot.new()
    graphics::rect(0, 0, 1, 1, col = "tomato", border = NA)
    graphics::text(0.5, 0.5, "OK")
    grDevices::dev.off()
    image <- ellmer::ContentImageInline(
      "image/png",
      openssl::base64_encode(readBin(png_path, "raw", file.info(png_path)$size))
    )
    pdf <- ellmer::ContentPDF(
      "application/pdf",
      openssl::base64_encode(readBin(pdf_path, "raw", file.info(pdf_path)$size)),
      "live-input.pdf"
    )
    rich_chat <- ellmercodex::chat_codex(model = model, echo = "none")
    rich_chunks <- coro::collect(rich_chat$stream(
      image,
      pdf,
      "Reply with exactly: live image and PDF input ok",
      stream = "text"
    ))
    rich_text <- require_nonempty_text(collapse_stream_text(rich_chunks), "rich input")
    writeLines(rich_text, artifact("live-rich-input.txt"), useBytes = TRUE)
    rich_turns <- save_turn_artifacts(rich_chat, "live-rich-input")
    assert_exact_text(rich_text, "live image and PDF input ok", "rich input")
    assert_exact_text(
      rich_turns[[length(rich_turns)]]@text,
      "live image and PDF input ok",
      "rich input history"
    )

    cancel_chat <- ellmercodex::chat_codex(model = model, echo = "none")
    controller <- ellmer::stream_controller()
    cancel_tool <- ellmer::tool(
      function(city) paste("Sunny in", city),
      name = "get_weather",
      description = "Get the weather for a city.",
      arguments = list(city = ellmer::type_string())
    )
    cancel_chat$register_tool(cancel_tool)
    cancel_chat$on_tool_request(function(request) controller$cancel())
    cancel_chunks <- coro::collect(cancel_chat$stream(
      "You must call get_weather with city Montevideo. Do not answer directly.",
      stream = "content",
      controller = controller
    ))
    writeLines(
      vapply(cancel_chunks, function(value) paste(class(value), collapse = "/"), character(1)),
      artifact("live-cancel-chunks.txt"),
      useBytes = TRUE
    )
    cancel_turns <- save_turn_artifacts(cancel_chat, "live-cancel")
    if (!isTRUE(controller$cancelled) || length(cancel_turns) != 2L ||
        !any(vapply(cancel_chunks, inherits, logical(1), what = "ellmer::ContentToolRequest"))) {
      stop("tool cancellation did not stop after the first Codex round.", call. = FALSE)
    }

    status$status <- "passed"
    status$passed <- TRUE
    write_json(status, artifact("live-status.json"))
    status
  }, error = function(error) {
    status$status <- "failed"
    status$passed <- FALSE
    status$error <- list(
      class = class(error),
      message = conditionMessage(error)
    )
    write_error(error, artifact("live-error.txt"))
    write_json(status, artifact("live-status.json"))
    status
  })
}

main <- function() {
  log_connection <- file(artifact("run.log"), open = "wt", encoding = "UTF-8")
  message_connection <- file(artifact("messages.log"), open = "wt", encoding = "UTF-8")
  sink(log_connection, split = TRUE)
  sink(message_connection, type = "message")
  on.exit({
    if (sink.number(type = "message") > 0L) {
      sink(NULL, type = "message")
    }
    while (sink.number() > 0L) sink(NULL)
    close(message_connection)
    close(log_connection)
  }, add = TRUE)

  cat("ellmercodex verification run\n")
  cat("project:", project_root, "\n")
  cat("output:", run_dir, "\n")
  cat("live checks:", truthy(Sys.getenv("ELLMERCODEX_RUN_LIVE_TESTS", unset = "false")), "\n\n")

  writeLines(capture.output(sessionInfo()), artifact("session-info.txt"), useBytes = TRUE)

  # ListReporter is intentionally used alone. MultiReporter can interfere
  # with later/coro scheduling in the async fixture tests. We generate a
  # small JUnit document from the stable ListReporter result set below.
  list_reporter <- testthat::ListReporter$new()

  suite_error <- NULL
  tryCatch(
    testthat::test_dir(
      test_dir,
      reporter = list_reporter,
      load_package = "source",
      package = "ellmercodex",
      stop_on_failure = FALSE,
      stop_on_warning = FALSE
    ),
    error = function(error) suite_error <<- error
  )

  test_results <- list_reporter$get_results()
  saveRDS(test_results, artifact("test-results.rds"))
  rows <- if (length(test_results) == 0L) {
    data.frame(
      file = character(), context = character(), test = character(),
      status = character(), warnings = integer(), expectations = integer(),
      user_seconds = numeric(), system_seconds = numeric(), real_seconds = numeric(),
      stringsAsFactors = FALSE
    )
  } else {
    do.call(rbind, lapply(test_results, test_row))
  }
  utils::write.csv(rows, artifact("test-results.csv"), row.names = FALSE)
  write_junit_xml(rows, artifact("test-results.xml"), suite_error = suite_error)

  suite_status <- if (!is.null(suite_error)) {
    "runner_error"
  } else if (any(rows$status == "fail")) {
    "failed"
  } else {
    "passed"
  }
  summary <- list(
    status = suite_status,
    tests = nrow(rows),
    expectations = sum(rows$expectations),
    passed = sum(rows$status == "pass"),
    skipped = sum(rows$status == "skip"),
    failed = sum(rows$status == "fail"),
    warnings = sum(rows$warnings),
    output_directory = run_dir
  )
  if (!is.null(suite_error)) {
    summary$error = list(class = class(suite_error), message = conditionMessage(suite_error))
    write_error(suite_error, artifact("test-runner-error.txt"))
  }
  write_json(summary, artifact("test-summary.json"))

  # Load the current source tree for the redacted diagnostics and optional
  # live checks. No credential object or provider object is serialized.
  pkgload::load_all(project_root, quiet = TRUE)
  package_version <- as.character(utils::packageVersion("ellmercodex"))
  ellmer_version <- as.character(utils::packageVersion("ellmer"))
  chat_methods <- names(getFromNamespace("Chat", "ellmer")$public_methods)
  api_inventory <- list(
    package = "ellmercodex",
    package_version = package_version,
    exports = sort(getNamespaceExports("ellmercodex")),
    ellmer_version = ellmer_version,
    chat_public_methods = chat_methods,
    separately_blocked_helpers = c(
      "parallel_chat", "parallel_chat_text", "parallel_chat_structured",
      "batch_chat", "batch_chat_text", "batch_chat_structured",
      "batch_chat_completed"
    )
  )
  write_json(api_inventory, artifact("api-inventory.json"))
  writeLines(capture.output(str(api_inventory)), artifact("api-inventory.txt"), useBytes = TRUE)

  diagnostics <- getFromNamespace("codex_diagnostics", "ellmercodex")(FALSE)
  write_json(diagnostics, artifact("diagnostics.json"))
  fixture_auth <- structure(
    list(
      access_token = "offline-fixture-access-token",
      refresh_token = "offline-fixture-refresh-token",
      account_id = "offline-fixture-account",
      expires_at = as.numeric(Sys.time()) + 3600
    ),
    class = c("codex_auth", "list")
  )
  write_json(
    ellmercodex::codex_account(fixture_auth),
    artifact("account-redacted.json")
  )
  writeLines(
    paste("codex_available:", ellmercodex::codex_available(FALSE)),
    artifact("availability.txt"),
    useBytes = TRUE
  )

  live_status <- run_live_checks()
  offline_passed <- identical(suite_status, "passed")
  overall_passed <- offline_passed && (!isTRUE(live_status$enabled) || isTRUE(live_status$passed))
  final <- list(
    status = if (overall_passed) "passed" else "failed",
    offline_suite = summary,
    live = live_status,
    output_directory = run_dir
  )
  write_json(final, artifact("run-status.json"))

  cat("\nOffline suite:", suite_status, "(", nrow(rows), "tests)\n", sep = "")
  cat("Overall:", if (overall_passed) "passed" else "failed", "\n")
  cat("Artifacts:", run_dir, "\n")
  if (!overall_passed) quit(save = "no", status = 1L, runLast = FALSE)
  invisible(final)
}

main()

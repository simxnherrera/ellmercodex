# Version-gated ellmer 0.4.2 compatibility layer.
#
# The public Chat object remains the package's external seam. This file owns
# the one private ellmer seam that is unavoidable for a stream-only Codex
# endpoint: Chat's private execution methods are replaced with methods that
# still use ellmer's Chat, TurnAccumulator, tool invocation helpers, callbacks,
# cancellation, and history machinery. The methods are installed with the Chat
# enclosing environment as their environment, so R6 cloning rewrites
# self/private for the clone instead of retaining a closure over the original
# Chat.

.codex_ellmer_compatibility_state <- new.env(parent = emptyenv())
.codex_ellmer_compatibility_state$provider_class <- NULL
.codex_ellmer_compatibility_state$methods_registered <- FALSE

codex_ellmer_chat_interface <- function() {
  list(
    class = c("Chat", "R6"),
    public_fields = character(),
    methods = list(
      initialize = "function(provider, system_prompt = NULL, echo = \"none\")",
      get_turns = "function(include_system_prompt = FALSE)",
      set_turns = "function(value)",
      add_turn = "function(user, assistant, log_tokens = TRUE)",
      get_system_prompt = "function()",
      get_model = "function()",
      set_model = "function(model)",
      set_system_prompt = "function(value)",
      get_tokens = "function(include_system_prompt = deprecated())",
      get_cost = "function(include = c(\"all\", \"last\"))",
      last_turn = "function(role = c(\"assistant\", \"user\", \"system\"))",
      chat = "function(..., echo = NULL)",
      chat_structured = "function(..., type, echo = \"none\", convert = TRUE)",
      chat_structured_async = "function(..., type, echo = \"none\", convert = TRUE)",
      chat_async = "function(..., tool_mode = c(\"concurrent\", \"sequential\"))",
      stream = "function(..., stream = c(\"text\", \"content\"), controller = NULL)",
      stream_async = paste0(
        "function(..., tool_mode = c(\"concurrent\", \"sequential\"), ",
        "stream = c(\"text\", \"content\"), controller = NULL)"
      ),
      register_tool = "function(tool)",
      register_tools = "function(tools)",
      get_provider = "function()",
      get_tools = "function()",
      set_tools = "function(tools)",
      on_tool_request = "function(callback)",
      on_tool_result = "function(callback)",
      clone = "function(deep = FALSE)"
    ),
    formal_names = list(
      initialize = c("provider", "system_prompt", "echo"),
      get_turns = "include_system_prompt",
      set_turns = "value",
      add_turn = c("user", "assistant", "log_tokens"),
      get_system_prompt = character(),
      get_model = character(),
      set_model = "model",
      set_system_prompt = "value",
      get_tokens = "include_system_prompt",
      get_cost = "include",
      last_turn = "role",
      chat = c("...", "echo"),
      chat_structured = c("...", "type", "echo", "convert"),
      chat_structured_async = c("...", "type", "echo", "convert"),
      chat_async = c("...", "tool_mode"),
      stream = c("...", "stream", "controller"),
      stream_async = c("...", "tool_mode", "stream", "controller"),
      register_tool = "tool",
      register_tools = "tools",
      get_provider = character(),
      get_tools = character(),
      set_tools = "tools",
      on_tool_request = "callback",
      on_tool_result = "callback",
      clone = "deep"
    ),
    inherited_public_behavior = list(
      R6_clone = "clone(deep = FALSE)",
      Chat_print = "print(x, ...)",
      R6_format = "format(x, ...)"
    ),
    private_state_used_by_compatibility = c(
      "provider", ".turns", "echo", "tools", "callback_on_tool_request",
      "callback_on_tool_result", "chat_impl", "chat_impl_async",
      "submit_turns", "submit_turns_async", "complete_dangling_tool_requests"
    )
  )
}

codex_ellmer_s7_class <- function() {
  codex_ellmer_compatibility()
  if (is.null(.codex_ellmer_compatibility_state$provider_class)) {
    parent <- utils::getFromNamespace("ProviderOpenAI", "ellmer")
    .codex_ellmer_compatibility_state$provider_class <- S7::new_class(
      "CodexProvider",
      parent = parent,
      package = "ellmercodex",
      properties = list(
        auth_ref = S7::class_environment
      )
    )
  }
  .codex_ellmer_compatibility_state$provider_class
}

codex_ellmer_s7_parent_method <- function(generic, class) {
  methods <- attr(utils::getFromNamespace(generic, "ellmer"), "methods")
  key <- paste0("ellmer::", class)
  if (!exists(key, envir = methods, inherits = FALSE)) {
    rlang::abort(
      paste0("ellmer 0.4.2 does not expose the expected ", generic,
             " method for ", class, "."),
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  get(key, envir = methods, inherits = FALSE)
}

codex_ellmer_provider_method <- function(generic, class, method) {
  generic_object <- utils::getFromNamespace(generic, "ellmer")
  S7::method(generic_object, class) <- method
  invisible(method)
}

codex_auth_reference <- function(auth, persist = FALSE) {
  if (!inherits(auth, "codex_auth")) {
    rlang::abort(
      "The Codex authentication object is invalid.",
      class = "codex_chat_error",
      parent = NULL
    )
  }
  reference <- new.env(parent = emptyenv())
  reference$auth <- auth
  reference$persist <- isTRUE(persist)
  reference$refreshing <- FALSE
  reference
}

codex_provider_access_token <- function(reference) {
  auth <- reference$auth
  if (!inherits(auth, "codex_auth")) {
    rlang::abort(
      "The Codex credential reference no longer contains a valid credential.",
      class = "codex_authentication_error",
      parent = NULL
    )
  }

  expires_at <- codex_token_expires_at(auth)
  has_expiry <- length(expires_at) == 1L && is.finite(expires_at)
  if (isTRUE(has_expiry) && expires_at <= as.numeric(Sys.time()) + 60) {
    if (!codex_auth_scalar_character(auth$refresh_token)) {
      rlang::abort(
        "The Codex access token expired and no refresh token was injected.",
        class = "codex_authentication_error",
        parent = NULL
      )
    }
    if (isTRUE(reference$refreshing)) {
      rlang::abort(
        "The Codex credential refresh was re-entered while a request was active.",
        class = "codex_authentication_error",
        parent = NULL
      )
    }
    reference$refreshing <- TRUE
    on.exit(reference$refreshing <- FALSE, add = TRUE)
    refreshed <- codex_refresh(auth, persist = reference$persist)
    reference$auth <- refreshed
    # Refreshing an injected credential must update the in-memory session, but
    # it must never fall back to loading a keyring credential. Persistence is
    # controlled solely by the reference created by the caller.
    codex_session_set(refreshed, persist = reference$persist)
    auth <- refreshed
  }

  token <- codex_auth_field(auth, "access_token", "accessToken")
  if (!codex_auth_scalar_character(token)) {
    rlang::abort(
      "The Codex credential did not contain an access token.",
      class = "codex_authentication_error",
      parent = NULL
    )
  }
  token
}

codex_provider_headers <- function(provider) {
  reference <- provider@auth_ref
  # This call is deliberately the only refresh gate used by the Chat
  # transport. All sync, async, tool, and helper requests reach it through the
  # same provider request method.
  codex_provider_access_token(reference)
  auth <- reference$auth
  account_id <- codex_auth_field(
    auth,
    "account_id", "chatgpt_account_id", "chatgptAccountId"
  )
  if (!codex_auth_scalar_character(account_id)) {
    rlang::abort(
      "The Codex credential is missing its account identifier.",
      class = "codex_authentication_error",
      parent = NULL
    )
  }
  c(
    `ChatGPT-Account-Id` = account_id,
    originator = codex_originator(),
    `OpenAI-Beta` = codex_protocol_version(),
    Accept = "text/event-stream",
    `User-Agent` = codex_user_agent()
  )
}

codex_provider_credentials <- function(reference) {
  codex_provider_access_token(reference)
}

codex_provider_body <- function(provider, stream = TRUE, turns = list(), tools = list(), type = NULL) {
  # The parent OpenAI Responses serializer is the source of truth for all
  # ellmer Content and Turn input forms, including images, PDFs, tool
  # requests/results, and provider-native tool declarations.
  parent <- codex_ellmer_s7_parent_method("chat_body", "ProviderOpenAI")
  body <- parent(
    provider = provider,
    stream = TRUE,
    turns = turns,
    tools = tools,
    type = type
  )
  body$stream <- TRUE
  body
}

codex_provider_request <- function(provider, stream = TRUE, turns = list(), tools = list(), type = NULL) {
  if (!isTRUE(stream)) {
    rlang::abort(
      paste(
        "ellmer's parallel and batch helpers request a non-streaming",
        "transport, but the Codex subscription endpoint requires stream = TRUE.",
        "Use the Chat methods; parallel_chat()/batch_chat() are explicitly",
        "blocked for this provider until ellmer or Codex exposes a compatible",
        "streaming helper."
      ),
      class = c("codex_ellmer_parallel_batch_blocker",
                "codex_ellmer_compatibility_error"),
      parent = NULL
    )
  }

  # Refresh before constructing the request, then let ellmer's base request
  # method attach the current bearer token. No keyring lookup is performed.
  codex_provider_access_token(provider@auth_ref)
  provider@extra_headers <- codex_provider_headers(provider)

  base_request <- utils::getFromNamespace("base_request", "ellmer")
  chat_path <- utils::getFromNamespace("chat_path", "ellmer")
  modify_list <- utils::getFromNamespace("modify_list", "ellmer")
  req <- base_request(provider)
  req <- httr2::req_url_path_append(req, chat_path(provider))
  body <- codex_provider_body(provider, stream = TRUE, turns = turns, tools = tools, type = type)
  body <- modify_list(body, provider@extra_args)
  # api_args is allowed to contain arbitrary Responses arguments, but cannot
  # disable streaming on this transport.
  body$stream <- TRUE
  req <- httr2::req_body_json(req, body)
  httr2::req_headers(req, !!!provider@extra_headers)
}

codex_provider_stream_parse <- function(provider, event) {
  if (is.null(event)) return(NULL)
  data <- if (is.list(event) && !is.null(event$data)) event$data else event
  if (is.character(data) && length(data) == 1L && identical(data, "[DONE]")) {
    return(NULL)
  }
  if (!is.character(data) || length(data) != 1L || is.na(data)) {
    codex_sse_protocol_error("The Codex stream event was not text.")
  }
  value <- tryCatch(
    jsonlite::fromJSON(data, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (!is.list(value)) {
    codex_sse_protocol_error("The Codex stream event contained invalid JSON.")
  }
  event_name <- if (is.list(event)) event$event else NULL
  if (is.null(value$type) && is.character(event_name) && length(event_name) == 1L) {
    value$type <- event_name
  }
  value
}

codex_stream_event_item <- function(event) {
  if (!is.list(event)) return(NULL)
  item <- event$item
  if (!is.list(item)) item <- NULL
  item
}

codex_stream_event_type <- function(event) {
  if (!is.list(event)) return(NULL)
  type <- event$type
  if (is.character(type) && length(type) == 1L && !is.na(type) && nzchar(type)) {
    type
  } else {
    NULL
  }
}

codex_stream_scalar <- function(value) {
  if (is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)) {
    value
  } else {
    NULL
  }
}

codex_stream_item_type <- function(item) {
  type <- if (is.list(item)) item$type else NULL
  if (is.character(type) && length(type) == 1L && !is.na(type)) type else NULL
}

codex_stream_item_key <- function(item, event = NULL, fallback = NULL) {
  type <- codex_stream_item_type(item)
  id <- if (is.list(item)) item$id else NULL
  call_id <- if (is.list(item)) item$call_id else NULL
  event_id <- if (is.list(event)) {
    event$item_id %||% event$output_item_id %||% event$call_id
  } else {
    NULL
  }
  # Responses argument deltas identify an item by item_id, while the
  # completed function-call object also contains call_id. Use item id first
  # so added/delta/done/terminal events address one ordered item.
  value <- id %||% call_id %||% event_id
  if (is.numeric(value) && length(value) == 1L && is.finite(value)) {
    value <- format(value, scientific = FALSE, trim = TRUE)
  }
  if (is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)) {
    return(paste0(type %||% "item", ":", value))
  }
  if (!is.null(fallback)) return(paste0(type %||% "item", ":", fallback))
  NULL
}

codex_stream_merge_item <- function(old, new) {
  if (!is.list(old)) return(new)
  if (!is.list(new)) return(old)
  merged <- old
  for (name in names(new)) {
    value <- new[[name]]
    if (is.null(value)) next
    if (is.list(value) && is.list(merged[[name]])) {
      merged[[name]] <- utils::modifyList(merged[[name]], value)
    } else {
      merged[[name]] <- value
    }
  }
  merged
}

codex_stream_state <- function(result = NULL) {
  if (is.list(result) && is.list(result$codex_items) &&
      is.character(result$codex_keys) && is.character(result$codex_order)) {
    return(result)
  }
  list(
    id = NULL,
    status = NULL,
    usage = NULL,
    incomplete_details = NULL,
    service_tier = NULL,
    output = list(),
    codex_items = list(),
    codex_keys = character(),
    codex_order = character(),
    codex_text_counter = 0L,
    codex_reasoning_counter = 0L,
    codex_terminal_seen = FALSE
  )
}

codex_stream_state_set_item <- function(state, key, item) {
  index <- match(key, state$codex_keys)
  if (is.na(index)) {
    state$codex_keys <- c(state$codex_keys, key)
    state$codex_order <- c(state$codex_order, key)
    state$codex_items[[length(state$codex_items) + 1L]] <- item
  } else {
    state$codex_items[[index]] <- codex_stream_merge_item(
      state$codex_items[[index]],
      item
    )
  }
  state$output <- state$codex_items
  state
}

codex_stream_state_append_text <- function(state, text) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    codex_sse_protocol_error("The Codex output text delta was malformed.")
  }
  if (!nzchar(text)) return(state)
  last <- if (length(state$codex_order)) tail(state$codex_order, 1L) else NULL
  if (is.character(last) && startsWith(last, "text:")) {
    index <- match(last, state$codex_keys)
    item <- state$codex_items[[index]]
    item$content[[1L]]$text <- paste0(item$content[[1L]]$text, text)
    state$codex_items[[index]] <- item
  } else {
    state$codex_text_counter <- state$codex_text_counter + 1L
    key <- paste0("text:", state$codex_text_counter)
    state$codex_keys <- c(state$codex_keys, key)
    state$codex_order <- c(state$codex_order, key)
    state$codex_items[[length(state$codex_items) + 1L]] <- list(
      type = "message",
      content = list(list(type = "output_text", text = text))
    )
  }
  state$output <- state$codex_items
  state
}

codex_stream_state_append_thinking <- function(state, thinking, extra = NULL) {
  if (!is.character(thinking) || length(thinking) != 1L || is.na(thinking) || !nzchar(thinking)) {
    return(state)
  }
  last <- if (length(state$codex_order)) tail(state$codex_order, 1L) else NULL
  if (is.character(last) && startsWith(last, "reasoning:")) {
    index <- match(last, state$codex_keys)
    item <- state$codex_items[[index]]
    item$summary[[1L]]$text <- paste0(item$summary[[1L]]$text, thinking)
    state$codex_items[[index]] <- item
  } else {
    state$codex_reasoning_counter <- state$codex_reasoning_counter + 1L
    key <- paste0("reasoning:", state$codex_reasoning_counter)
    state$codex_keys <- c(state$codex_keys, key)
    state$codex_order <- c(state$codex_order, key)
    state$codex_items[[length(state$codex_items) + 1L]] <- Filter(
      Negate(is.null),
      list(
        type = "reasoning",
        summary = list(list(type = "summary_text", text = thinking)),
        extra = extra
      )
    )
  }
  state$output <- state$codex_items
  state
}

codex_stream_state_upsert_event_item <- function(state, event, item) {
  type <- codex_stream_item_type(item)
  # Empty message placeholders are completed by output_text deltas. Adding one
  # here would create a duplicate message in the final turn.
  if (identical(type, "message") &&
      (!is.list(item$content) || length(item$content) == 0L)) {
    return(state)
  }
  key <- codex_stream_item_key(item, event = event, fallback = length(state$codex_items) + 1L)
  if (is.null(key)) return(state)
  codex_stream_state_set_item(state, key, item)
}

codex_stream_terminal <- function(event) {
  terminal <- if (is.list(event)) event$response else NULL
  if (!is.list(terminal) && is.list(event) && is.list(event$output)) terminal <- event
  if (!is.list(terminal)) terminal <- list()
  terminal
}

codex_stream_state_merge_terminal <- function(state, terminal) {
  if (!is.list(terminal)) return(state)
  state$codex_terminal_seen <- TRUE
  for (name in c("id", "status", "usage", "incomplete_details", "service_tier")) {
    if (!is.null(terminal[[name]])) state[[name]] <- terminal[[name]]
  }
  output <- terminal$output
  if (!is.list(output)) {
    state$output <- state$codex_items
    return(state)
  }

  streamed_text <- any(vapply(
    state$codex_items,
    function(item) {
      is.list(item) && identical(item$type, "message") && is.list(item$content) &&
        any(vapply(item$content, function(content) {
          is.list(content) && identical(content$type, "output_text") &&
            is.character(content$text) && nzchar(content$text)
        }, logical(1)))
    },
    logical(1)
  ))

  for (i in seq_along(output)) {
    item <- output[[i]]
    if (!is.list(item)) next
    if (identical(item$type, "reasoning") && any(vapply(
      state$codex_items,
      function(value) is.list(value) && identical(value$type, "reasoning"),
      logical(1)
    ))) {
      next
    }
    if (identical(item$type, "message") && streamed_text) {
      # The endpoint often repeats an aggregated message in the terminal
      # object even though its deltas already established text/tool/text
      # ordering. Keep the streamed order and only retain non-text payloads.
      non_text <- if (is.list(item$content)) Filter(function(content) {
        !is.list(content) || !identical(content$type, "output_text")
      }, item$content) else list()
      if (length(non_text)) {
        for (content in non_text) {
          synthetic <- list(type = "codex_terminal_content", content = list(content))
          key <- paste0("terminal:", i, ":", length(state$codex_items) + 1L)
          state <- codex_stream_state_set_item(state, key, synthetic)
        }
      }
      next
    }
    state <- codex_stream_state_upsert_event_item(state, list(), item)
  }
  state$output <- state$codex_items
  state
}

codex_stream_merge <- function(provider, result, chunk) {
  state <- codex_stream_state(result)
  if (is.null(chunk)) return(state)
  type <- codex_stream_event_type(chunk)
  if (is.null(type)) return(state)

  if (identical(type, "response.output_text.delta")) {
    if (!is.null(chunk$delta)) state <- codex_stream_state_append_text(state, chunk$delta)
  } else if (identical(type, "response.output_text.done")) {
    # The delta sequence is authoritative when present. If there were no
    # deltas, the terminal/text-done event is still a real output item.
    has_text <- any(vapply(state$codex_items, function(item) {
      is.list(item) && identical(item$type, "message") && is.list(item$content) &&
        any(vapply(item$content, function(content) {
          is.list(content) && identical(content$type, "output_text")
        }, logical(1)))
    }, logical(1)))
    if (!has_text && !is.null(chunk$text)) {
      state <- codex_stream_state_append_text(state, chunk$text)
    }
  } else if (identical(type, "response.reasoning_summary_text.delta")) {
    state <- codex_stream_state_append_thinking(state, chunk$delta)
  } else if (identical(type, "response.output_item.added") ||
             identical(type, "response.output_item.done")) {
    item <- codex_stream_event_item(chunk)
    if (!is.null(item)) state <- codex_stream_state_upsert_event_item(state, chunk, item)
  } else if (identical(type, "response.function_call_arguments.delta")) {
    key <- codex_stream_item_key(
      list(type = "function_call"), event = chunk,
      fallback = chunk$item_id %||% chunk$call_id %||% (length(state$codex_items) + 1L)
    )
    index <- match(key, state$codex_keys)
    if (is.na(index)) {
      item <- Filter(Negate(is.null), list(
        type = "function_call",
        id = chunk$item_id,
        call_id = chunk$call_id,
        arguments = ""
      ))
      state <- codex_stream_state_set_item(state, key, item)
      index <- match(key, state$codex_keys)
    }
    delta <- chunk$delta
    if (!is.character(delta) || length(delta) != 1L || is.na(delta)) {
      codex_sse_protocol_error("The Codex function-call argument delta was malformed.")
    }
    item <- state$codex_items[[index]]
    item$arguments <- paste0(item$arguments %||% "", delta)
    state$codex_items[[index]] <- item
    state$output <- state$codex_items
  } else if (identical(type, "response.function_call_arguments.done")) {
    key <- codex_stream_item_key(
      list(type = "function_call"), event = chunk,
      fallback = chunk$item_id %||% chunk$call_id %||% (length(state$codex_items) + 1L)
    )
    index <- match(key, state$codex_keys)
    if (is.na(index)) {
      item <- Filter(Negate(is.null), list(
        type = "function_call",
        id = chunk$item_id,
        call_id = chunk$call_id,
        arguments = chunk$arguments
      ))
      state <- codex_stream_state_set_item(state, key, item)
    } else {
      item <- state$codex_items[[index]]
      item$arguments <- chunk$arguments
      state$codex_items[[index]] <- item
      state$output <- state$codex_items
    }
  } else if (type %in% c("response.completed", "response.done", "response.incomplete")) {
    state <- codex_stream_state_merge_terminal(state, codex_stream_terminal(chunk))
  } else if (identical(type, "response.failed")) {
    codex_sse_error(chunk, "Codex generation failed.")
  } else if (identical(type, "error")) {
    codex_sse_error(chunk)
  }
  state
}

codex_stream_output_text <- function(item) {
  if (!is.list(item)) return(character())
  if (identical(item$type, "message") && is.list(item$content)) {
    return(vapply(item$content, function(content) {
      if (is.list(content) && identical(content$type, "output_text") &&
          is.character(content$text) && length(content$text) == 1L) content$text else ""
    }, character(1)))
  }
  if (identical(item$type, "output_text") && is.character(item$text)) item$text else character()
}

codex_stream_output_format <- function(item) {
  format <- if (is.list(item)) item$output_format else NULL
  if (identical(format, "png")) "image/png"
  else if (identical(format, "jpeg")) "image/jpeg"
  else if (identical(format, "webp")) "image/webp"
  else if (is.character(format) && length(format) == 1L && nzchar(format)) format
  else "application/octet-stream"
}

codex_stream_content_from_item <- function(item) {
  if (!is.list(item)) return(NULL)
  type <- codex_stream_item_type(item)
  if (identical(type, "image_generation_call")) {
    data <- item$result %||% item$data
    if (is.character(data) && length(data) == 1L && !is.na(data)) {
      return(ellmer::ContentImageInline(codex_stream_output_format(item), data))
    }
  }
  if (type %in% c("image", "output_image")) {
    data <- item$data %||% item$result
    url <- item$url %||% item$image_url
    if (is.character(data) && length(data) == 1L) {
      return(ellmer::ContentImageInline(item$mime_type %||% "image/png", data))
    }
    if (is.character(url) && length(url) == 1L) {
      return(ellmer::ContentImageRemote(url, detail = item$detail %||% ""))
    }
  }
  if (type %in% c("file", "output_file", "pdf")) {
    data <- item$file_data %||% item$data %||% item$result
    filename <- item$filename %||% item$name %||% "output.pdf"
    mime <- item$mime_type %||% if (identical(type, "pdf")) {
      "application/pdf"
    } else {
      "application/octet-stream"
    }
    if (is.character(data) && length(data) == 1L &&
        is.character(filename) && length(filename) == 1L) {
      return(ellmer::ContentPDF(mime, data, filename))
    }
  }
  if (identical(type, "function_call")) {
    # The compatibility chat loop suppresses its second copy from
    # invoke_tools(), so the request can remain at its provider position in a
    # content stream.
    return(codex_tool_request_from_item(item))
  }
  if (identical(type, "web_search_call")) {
    # Search/tool requests are yielded by the outer tool loop, as with the
    # function-call path. The completed turn retains the full provider item.
    return(NULL)
  }
  if (identical(type, "reasoning")) {
    # Reasoning summary deltas are the streamable form. Returning the complete
    # done item as well would duplicate thinking in `stream(stream="content")`.
    return(NULL)
  }
  # Retain new/non-standard Responses output items in content streaming. The
  # corresponding completed turn uses the same ContentJson representation.
  codex_content_json(data = item)
}

codex_provider_stream_content <- function(provider, event) {
  type <- codex_stream_event_type(event)
  if (identical(type, "response.output_text.delta")) {
    if (is.null(event$delta)) return(NULL)
    return(ellmer::ContentText(event$delta))
  }
  if (identical(type, "response.reasoning_summary_text.delta")) {
    if (is.null(event$delta)) return(NULL)
    return(ellmer::ContentThinking(event$delta))
  }
  if (identical(type, "response.output_item.done")) {
    return(codex_stream_content_from_item(codex_stream_event_item(event)))
  }
  NULL
}

codex_terminal_stream_contents <- function(
  result,
  streamed_item_keys = character(),
  streamed_text = FALSE
) {
  output <- if (is.list(result)) result$output else NULL
  if (!is.list(output)) return(list())

  contents <- list()
  for (i in seq_along(output)) {
    item <- output[[i]]
    if (!is.list(item)) next
    key <- codex_stream_item_key(item, fallback = i)
    if (!is.null(key) && key %in% streamed_item_keys) next

    if (identical(item$type, "message")) {
      # A terminal message commonly repeats text already emitted through
      # output_text deltas. When it is the only representation, emit its text
      # now so a terminal-only response still satisfies stream semantics.
      if (isTRUE(streamed_text)) next
      message_contents <- if (is.list(item$content)) item$content else list()
      for (value in message_contents) {
        if (is.list(value) && identical(value$type, "output_text") &&
            is.character(value$text) && length(value$text) == 1L) {
          contents[[length(contents) + 1L]] <- ellmer::ContentText(value$text)
        }
      }
      next
    }

    content <- codex_stream_content_from_item(item)
    if (!is.null(content)) contents[[length(contents) + 1L]] <- content
  }
  contents
}

codex_content_json <- function(data = NULL, string = NULL) {
  constructor <- utils::getFromNamespace("ContentJson", "ellmer")
  constructor(data = data, string = string)
}

codex_tool_arguments <- function(value) {
  if (is.list(value)) return(value)
  if (is.null(value) || (is.character(value) && length(value) == 1L && !nzchar(value))) {
    return(list())
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    codex_sse_protocol_error("The Codex function-call arguments were malformed.")
  }
  parsed <- tryCatch(jsonlite::fromJSON(value, simplifyVector = FALSE), error = function(error) NULL)
  if (!is.list(parsed)) {
    codex_sse_protocol_error("The Codex function-call arguments were not a JSON object.")
  }
  parsed
}

codex_tool_request_from_item <- function(item) {
  id <- item$call_id %||% item$id
  name <- item$name
  if (!is.character(id) || length(id) != 1L ||
      !is.character(name) || length(name) != 1L) {
    codex_sse_protocol_error("The Codex function-call item omitted its ID or name.")
  }
  extra <- Filter(Negate(is.null), list(
    item_id = item$id,
    output_index = item$output_index
  ))
  ellmer::ContentToolRequest(
    id = id,
    name = name,
    arguments = codex_tool_arguments(item$arguments),
    extra = extra
  )
}

codex_content_from_output_item <- function(item, has_type = FALSE) {
  if (!is.list(item)) return(list(codex_content_json(data = item)))
  type <- codex_stream_item_type(item)
  if (identical(type, "message")) {
    content <- item$content
    if (!is.list(content)) return(list())
    output_text <- vapply(content, function(value) {
      if (is.list(value) && identical(value$type, "output_text") && is.character(value$text)) value$text else ""
    }, character(1))
    if (isTRUE(has_type) && any(nzchar(output_text))) {
      return(list(codex_content_json(string = paste0(output_text[nzchar(output_text)], collapse = ""))))
    }
    return(codex_flatten_content_lists(lapply(content, function(value) {
      if (!is.list(value)) return(list(codex_content_json(data = value)))
      if (identical(value$type, "output_text") && is.character(value$text)) {
        return(list(ellmer::ContentText(value$text)))
      }
      if (identical(value$type, "refusal") && is.character(value$refusal)) {
        return(list(ellmer::ContentText(value$refusal)))
      }
      list(codex_content_json(data = value))
    })))
  }
  if (identical(type, "output_text") && is.character(item$text)) {
    return(list(if (has_type) codex_content_json(string = item$text) else ellmer::ContentText(item$text)))
  }
  if (identical(type, "function_call")) {
    return(list(codex_tool_request_from_item(item)))
  }
  if (identical(type, "reasoning")) {
    summary <- if (is.list(item$summary)) item$summary else list()
    thinking <- paste0(vapply(summary, function(value) {
      if (is.list(value) && is.character(value$text)) value$text else ""
    }, character(1)), collapse = "")
    return(list(ellmer::ContentThinking(thinking = thinking, extra = item)))
  }
  if (identical(type, "image_generation_call")) {
    data <- item$result %||% item$data
    if (is.character(data) && length(data) == 1L) {
      return(list(ellmer::ContentImageInline(codex_stream_output_format(item), data)))
    }
    return(list(codex_content_json(data = item)))
  }
  if (type %in% c("file", "output_file", "pdf")) {
    data <- item$file_data %||% item$data %||% item$result
    filename <- item$filename %||% item$name %||% "output.pdf"
    mime <- item$mime_type %||% "application/pdf"
    if (is.character(data) && length(data) == 1L) {
      return(list(ellmer::ContentPDF(mime, data, filename)))
    }
  }
  if (type %in% c("image", "output_image")) {
    data <- item$data %||% item$result
    url <- item$url %||% item$image_url
    if (is.character(data) && length(data) == 1L) {
      return(list(ellmer::ContentImageInline(item$mime_type %||% "image/png", data)))
    }
    if (is.character(url) && length(url) == 1L) {
      return(list(ellmer::ContentImageRemote(url, detail = item$detail %||% "")))
    }
  }
  if (identical(type, "web_search_call")) {
    action <- item$action
    query <- if (is.list(action)) action$query %||% action$url else NULL
    constructor <- utils::getFromNamespace("ContentToolRequestSearch", "ellmer")
    return(list(constructor(query = query %||% "web search", json = item)))
  }
  # Preserve terminal output and newly added Responses item kinds rather than
  # silently dropping them. ContentJson is ellmer's generic structured
  # content container and retains the exact provider item for a future
  # round-trip or explicit compatibility update.
  list(codex_content_json(data = item))
}

codex_flatten_content_lists <- function(values) {
  if (length(values) == 0L) return(list())
  Reduce(c, values, init = list())
}

codex_provider_value_turn <- function(provider, result, has_type = FALSE) {
  if (!is.list(result)) {
    rlang::abort(
      "The Codex stream did not produce a response object.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }
  if (!isTRUE(result$codex_terminal_seen)) {
    rlang::abort(
      "The Codex SSE stream ended without a terminal response event.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }
  if (identical(result$status, "failed")) {
    rlang::abort(
      "Codex generation failed.",
      class = "codex_generation_error",
      parent = NULL
    )
  }
  output <- result$output
  if (!is.list(output)) output <- list()
  contents <- codex_flatten_content_lists(
    lapply(output, codex_content_from_output_item, has_type = has_type)
  )
  if (length(contents) == 0L) {
    # A stream can contain output text deltas while the terminal response omits
    # output. The merge layer already materializes those deltas as message
    # items; reaching this branch means the endpoint sent no representable
    # content and must be reported instead of becoming an empty success.
    rlang::abort(
      "The Codex terminal response contained no representable assistant content.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }
  tokens <- codex_provider_value_tokens(provider, result)
  cost <- codex_provider_value_cost(provider, tokens, result)
  ellmer::AssistantTurn(
    contents = contents,
    json = codex_public_response(result),
    tokens = unlist(tokens),
    cost = cost,
    finish_reason = codex_provider_finish_reason(provider, result)
  )
}

codex_provider_value_tokens <- function(provider, json) {
  usage <- if (is.list(json)) json$usage else NULL
  if (!is.list(usage)) usage <- list()
  cached <- usage$input_tokens_details$cached_tokens %||%
    usage$prompt_tokens_details$cached_tokens %||% 0
  input_total <- usage$input_tokens %||% usage$prompt_tokens %||% 0
  output <- usage$output_tokens %||% usage$completion_tokens %||% 0
  numeric_value <- function(value) {
    value <- suppressWarnings(as.numeric(value))
    if (length(value) != 1L || !is.finite(value)) 0 else value
  }
  cached <- numeric_value(cached)
  input_total <- numeric_value(input_total)
  output <- numeric_value(output)
  constructor <- utils::getFromNamespace("tokens", "ellmer")
  constructor(
    input = max(0, input_total - cached),
    output = output,
    cached_input = cached
  )
}

codex_provider_value_cost <- function(provider, tokens, result) {
  reported <- result$usage$cost %||% result$cost
  reported <- suppressWarnings(as.numeric(reported))
  if (length(reported) == 1L && is.finite(reported)) {
    return(utils::getFromNamespace("dollars", "ellmer")(reported))
  }
  get_token_cost <- utils::getFromNamespace("get_token_cost", "ellmer")
  variant <- result$service_tier %||% "default"
  tryCatch(
    get_token_cost(provider, tokens, variant = variant),
    error = function(error) utils::getFromNamespace("dollars", "ellmer")(NA_real_)
  )
}

codex_provider_finish_reason <- function(provider, result) {
  status <- result$status
  if (identical(status, "incomplete")) {
    reason <- result$incomplete_details$reason %||% status
    return(switch(
      reason,
      max_output_tokens = "max_tokens",
      content_filter = "content_filter",
      as.character(reason)
    ))
  }
  output <- if (is.list(result)) result$output else NULL
  if (is.list(output) && any(vapply(output, function(item) {
    is.list(item) && identical(item$type, "function_call")
  }, logical(1)))) {
    return("tool_use")
  }
  if (is.null(status)) return(NA_character_)
  if (identical(status, "completed")) return("success")
  I(as.character(status))
}

codex_public_response <- function(result) {
  result[!startsWith(names(result), "codex_")]
}

codex_provider_finish_reason_method <- function(provider, result) {
  codex_provider_finish_reason(provider, result)
}

codex_register_ellmer_provider_methods <- function() {
  if (isTRUE(.codex_ellmer_compatibility_state$methods_registered)) return(invisible(TRUE))
  class <- codex_ellmer_s7_class()
  codex_ellmer_provider_method("chat_body", class, codex_provider_body)
  codex_ellmer_provider_method("chat_request", class, codex_provider_request)
  codex_ellmer_provider_method("stream_parse", class, codex_provider_stream_parse)
  codex_ellmer_provider_method("stream_content", class, codex_provider_stream_content)
  codex_ellmer_provider_method("stream_merge_chunks", class, codex_stream_merge)
  codex_ellmer_provider_method("value_turn", class, codex_provider_value_turn)
  codex_ellmer_provider_method("value_tokens", class, codex_provider_value_tokens)
  codex_ellmer_provider_method("value_finish_reason", class, codex_provider_finish_reason_method)
  codex_ellmer_provider_method("has_batch_support", class, function(provider) FALSE)
  .codex_ellmer_compatibility_state$methods_registered <- TRUE
  invisible(TRUE)
}

codex_new_provider <- function(model, auth, params = NULL, api_args = list(), persist = FALSE) {
  codex_ellmer_compatibility()
  codex_register_ellmer_provider_methods()
  class <- codex_ellmer_s7_class()
  reference <- codex_auth_reference(auth, persist = persist)
  provider <- class(
    name = "codex",
    model = model,
    base_url = sub("/responses$", "", codex_responses_url()),
    params = params %||% list(),
    extra_args = api_args,
    extra_headers = c(
      `ChatGPT-Account-Id` = codex_auth_field(auth, "account_id", "chatgpt_account_id", "chatgptAccountId"),
      originator = codex_originator(),
      `OpenAI-Beta` = codex_protocol_version(),
      Accept = "text/event-stream",
      `User-Agent` = codex_user_agent()
    ),
    credentials = function() codex_provider_credentials(reference),
    preserve_thinking = TRUE,
    service_tier = "default",
    auth_ref = reference
  )
  provider
}

codex_ellmer_private_submit <- function(
  user_turn,
  type = NULL,
  stream = FALSE,
  echo = "none",
  yield_as_content = FALSE,
  controller = NULL,
  otel_span = NULL
) {
  utils::getFromNamespace("codex_submit_turns_sync", "ellmercodex")(
    self = self,
    private = private,
    user_turn = user_turn,
    type = type,
    stream = stream,
    echo = echo,
    yield_as_content = yield_as_content,
    controller = controller,
    otel_span = otel_span
  )
}

codex_ellmer_private_submit_async <- function(
  user_turn,
  type = NULL,
  stream = FALSE,
  echo = "none",
  yield_as_content = FALSE,
  controller = NULL,
  otel_span = NULL
) {
  utils::getFromNamespace("codex_submit_turns_async", "ellmercodex")(
    self = self,
    private = private,
    user_turn = user_turn,
    type = type,
    stream = stream,
    echo = echo,
    yield_as_content = yield_as_content,
    controller = controller,
    otel_span = otel_span
  )
}

codex_install_private_submit_methods <- function(chat) {
  provider <- tryCatch(chat$get_provider(), error = function(error) NULL)
  if (is.null(provider) || !inherits(provider, "ellmercodex::CodexProvider")) {
    rlang::abort(
      "The compatibility installer requires a CodexProvider-backed ellmer Chat.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  private <- tryCatch(chat$.__enclos_env__$private, error = function(error) NULL)
  if (!is.environment(private)) {
    rlang::abort(
      "The ellmer Chat did not expose its private compatibility environment.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  required <- c(
    "provider", ".turns", "tools", "callback_on_tool_request",
    "callback_on_tool_result", "submit_turns", "submit_turns_async",
    "chat_impl", "chat_impl_async", "complete_dangling_tool_requests"
  )
  if (!all(vapply(required, exists, logical(1), envir = private, inherits = FALSE))) {
    rlang::abort(
      "The installed ellmer Chat private state is incompatible with 0.4.2.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }
  callbacks <- c("callback_on_tool_request", "callback_on_tool_result")
  callbacks_ok <- vapply(callbacks, function(name) {
    manager <- private[[name]]
    is.environment(manager) && is.function(manager$invoke) &&
      is.function(manager$invoke_async)
  }, logical(1))
  if (!all(callbacks_ok)) {
    rlang::abort(
      "The installed ellmer Chat callback managers are incompatible with 0.4.2.",
      class = "codex_ellmer_compatibility_error",
      parent = NULL
    )
  }

  methods <- list(
    chat_impl = codex_ellmer_private_chat_impl,
    chat_impl_async = codex_ellmer_private_chat_impl_async,
    submit_turns = codex_ellmer_private_submit,
    submit_turns_async = codex_ellmer_private_submit_async
  )
  locked <- rlang::env_binding_are_locked(private, names(methods))
  unlock <- names(methods)[locked]
  if (length(unlock)) rlang::env_binding_unlock(private, unlock)
  on.exit({
    if (length(unlock)) {
      relock <- unlock[!vapply(
        unlock,
        function(name) rlang::env_binding_are_locked(private, name),
        logical(1)
      )]
      if (length(relock)) rlang::env_binding_lock(private, relock)
    }
  }, add = TRUE)
  for (name in names(methods)) {
    method <- methods[[name]]
    environment(method) <- chat$.__enclos_env__
    private[[name]] <- method
  }
  attr(chat, "ellmercodex_compatibility") <- "ellmer-0.4.2-provider-stream"
  chat
}

codex_emit_stream_content <- function(content, emit, yield_as_content) {
  textual <- inherits(content, "ellmer::ContentText") ||
    inherits(content, "ellmer::ContentThinking")
  if (textual) {
    text <- utils::getFromNamespace("content_text", "ellmer")(content)
    emit(text)
  }
  if (isTRUE(yield_as_content)) content else if (textual) text else NULL
}

codex_tool_request_id <- function(value) {
  if (!inherits(value, "ellmer::ContentToolRequest")) return(NULL)
  id <- value@id
  if (is.character(id) && length(id) == 1L && !is.na(id)) id else NULL
}

codex_chat_impl_sync <- function(
  self,
  private,
  user_turn,
  stream,
  echo,
  yield_as_content = FALSE,
  controller = NULL
) {
  if (is.null(controller)) controller <- ellmer::stream_controller()
  coro::generator(function() {
    tool_errors <- list()
    on.exit(
      utils::getFromNamespace("warn_tool_errors", "ellmer")(tool_errors),
      add = TRUE
    )
    agent_span <- utils::getFromNamespace("local_agent_otel_span", "ellmer")(
      private$provider,
      activate = FALSE
    )

    while (!is.null(user_turn)) {
      streamed_tool_ids <- character()
      assistant_chunks <- private$submit_turns(
        user_turn,
        stream = stream,
        echo = echo,
        yield_as_content = yield_as_content,
        controller = controller,
        otel_span = agent_span
      )
      for (chunk in assistant_chunks) {
        id <- codex_tool_request_id(chunk)
        if (!is.null(id)) streamed_tool_ids <- c(streamed_tool_ids, id)
        coro::yield(chunk)
      }

      assistant_turn <- self$last_turn()
      user_turn <- NULL
      if (isTRUE(controller$cancelled)) break

      has_tool_request <- utils::getFromNamespace("turn_has_tool_request", "ellmer")
      if (has_tool_request(assistant_turn)) {
        tool_calls <- utils::getFromNamespace("invoke_tools", "ellmer")(
          assistant_turn,
          echo = echo,
          on_tool_request = private$callback_on_tool_request$invoke,
          on_tool_result = private$callback_on_tool_result$invoke,
          yield_request = TRUE,
          otel_span = agent_span
        )
        tool_results <- list()
        is_tool_request <- utils::getFromNamespace("is_tool_request", "ellmer")
        is_tool_result <- utils::getFromNamespace("is_tool_result", "ellmer")
        for (tool_step in tool_calls) {
          if (is_tool_request(tool_step)) {
            id <- codex_tool_request_id(tool_step)
            already_streamed <- !is.null(id) && id %in% streamed_tool_ids
            if (isTRUE(yield_as_content) && !already_streamed) {
              coro::yield(tool_step)
            }
          }
          if (is_tool_result(tool_step)) {
            if (isTRUE(yield_as_content)) coro::yield(tool_step)
            tool_results <- c(tool_results, list(tool_step))
          }
        }
        if (isTRUE(controller$cancelled)) break
        user_turn <- utils::getFromNamespace("tool_results_as_turn", "ellmer")(
          tool_results
        )
      }

      if (identical(echo, "all")) {
        cat(format(user_turn))
      } else if (identical(echo, "none")) {
        tool_errors <- c(
          tool_errors,
          utils::getFromNamespace("turn_get_tool_errors", "ellmer")(user_turn)
        )
      }
    }
  })()
}

codex_chat_impl_async <- function(
  self,
  private,
  user_turn,
  stream,
  echo,
  tool_mode = "concurrent",
  yield_as_content = FALSE,
  controller = NULL
) {
  if (is.null(controller)) controller <- ellmer::stream_controller()
  coro::async_generator(function() {
    tool_errors <- list()
    on.exit(
      utils::getFromNamespace("warn_tool_errors", "ellmer")(tool_errors),
      add = TRUE
    )
    agent_span <- utils::getFromNamespace("local_agent_otel_span", "ellmer")(
      private$provider,
      activate = FALSE
    )

    while (!is.null(user_turn)) {
      streamed_tool_ids <- character()
      assistant_chunks <- private$submit_turns_async(
        user_turn,
        stream = stream,
        echo = echo,
        yield_as_content = yield_as_content,
        controller = controller,
        otel_span = agent_span
      )
      for (chunk in coro::await_each(assistant_chunks)) {
        id <- codex_tool_request_id(chunk)
        if (!is.null(id)) streamed_tool_ids <- c(streamed_tool_ids, id)
        coro::yield(chunk)
      }

      assistant_turn <- self$last_turn()
      user_turn <- NULL
      if (isTRUE(controller$cancelled)) break

      has_tool_request <- utils::getFromNamespace("turn_has_tool_request", "ellmer")
      if (has_tool_request(assistant_turn)) {
        tool_calls <- utils::getFromNamespace("invoke_tools_async", "ellmer")(
          assistant_turn,
          private$tools,
          echo = echo,
          on_tool_request = private$callback_on_tool_request$invoke_async,
          on_tool_result = private$callback_on_tool_result$invoke_async,
          yield_request = TRUE,
          otel_span = agent_span
        )
        is_tool_request <- utils::getFromNamespace("is_tool_request", "ellmer")
        is_tool_result <- utils::getFromNamespace("is_tool_result", "ellmer")
        is_streamed_request <- function(value) {
          id <- codex_tool_request_id(value)
          !is.null(id) && id %in% streamed_tool_ids
        }

        if (identical(tool_mode, "sequential")) {
          tool_results <- list()
          for (tool_step in coro::await_each(tool_calls)) {
            if (is_tool_request(tool_step)) {
              if (isTRUE(yield_as_content) && !is_streamed_request(tool_step)) {
                coro::yield(tool_step)
              }
            } else if (is_tool_result(tool_step)) {
              if (isTRUE(yield_as_content)) coro::yield(tool_step)
              tool_results <- c(tool_results, list(tool_step))
            }
          }
        } else {
          tool_steps <- coro::collect(tool_calls)
          requests <- vapply(tool_steps, is_tool_request, logical(1))
          if (isTRUE(yield_as_content) && any(requests)) {
            for (tool_step in tool_steps[requests]) {
              if (!is_streamed_request(tool_step)) coro::yield(tool_step)
            }
          }
          pending <- tool_steps[!requests]
          tool_results <- coro::await(promises::promise_all(.list = pending))
          if (isTRUE(yield_as_content)) {
            for (tool_result in tool_results) coro::yield(tool_result)
          }
        }
        if (isTRUE(controller$cancelled)) break
        user_turn <- utils::getFromNamespace("tool_results_as_turn", "ellmer")(
          tool_results
        )
      }

      if (identical(echo, "all")) {
        cat(format(user_turn))
      } else if (identical(echo, "none")) {
        tool_errors <- c(
          tool_errors,
          utils::getFromNamespace("turn_get_tool_errors", "ellmer")(user_turn)
        )
      }
    }
  })()
}

codex_ellmer_private_chat_impl <- function(
  user_turn,
  stream,
  echo,
  yield_as_content = FALSE,
  controller = NULL
) {
  utils::getFromNamespace("codex_chat_impl_sync", "ellmercodex")(
    self = self,
    private = private,
    user_turn = user_turn,
    stream = stream,
    echo = echo,
    yield_as_content = yield_as_content,
    controller = controller
  )
}

codex_ellmer_private_chat_impl_async <- function(
  user_turn,
  stream,
  echo,
  tool_mode = "concurrent",
  yield_as_content = FALSE,
  controller = NULL
) {
  utils::getFromNamespace("codex_chat_impl_async", "ellmercodex")(
    self = self,
    private = private,
    user_turn = user_turn,
    stream = stream,
    echo = echo,
    tool_mode = tool_mode,
    yield_as_content = yield_as_content,
    controller = controller
  )
}

codex_submit_turns_sync <- function(
  self,
  private,
  user_turn,
  type = NULL,
  stream = FALSE,
  echo = "none",
  yield_as_content = FALSE,
  controller = NULL,
  otel_span = NULL
) {
  if (is.null(controller)) controller <- ellmer::stream_controller()
  provider <- private$provider
  tools <- if (is.null(type)) private$tools else NULL
  accumulator_class <- utils::getFromNamespace("TurnAccumulator", "ellmer")
  if (identical(echo, "all")) {
    utils::getFromNamespace("cat_line", "ellmer")(format(user_turn), prefix = "> ")
  }

  coro::generator(function() {
    request_turns <- c(private$.turns, list(user_turn))
    otel_input <- utils::getFromNamespace("otel_chat_input", "ellmer")(
      private,
      user_turn
    )
    chat_span <- utils::getFromNamespace("local_chat_otel_span", "ellmer")(
      provider,
      turns = otel_input$turns,
      system_prompt = otel_input$system_prompt,
      parent = otel_span
    )
    accumulator <- accumulator_class$new(self, private, controller)
    accumulator$begin_turn(user_turn)
    completed <- FALSE
    on.exit({
      if (!isTRUE(completed)) accumulator$finalize_turn()
    }, add = TRUE)

    request <- utils::getFromNamespace("chat_perform", "ellmer")(
      provider = provider,
      mode = "stream",
      turns = request_turns,
      tools = tools,
      type = type,
      otel_span = chat_span,
      controller = controller
    )

    emit <- utils::getFromNamespace("emitter", "ellmer")(echo)
    any_text <- FALSE
    streamed_item_keys <- character()
    streamed_text <- FALSE
    result <- NULL
    repeat {
      chunk <- request()
      if (coro::is_exhausted(chunk)) break
      if (identical(codex_stream_event_type(chunk), "response.output_item.done")) {
        item <- codex_stream_event_item(chunk)
        key <- codex_stream_item_key(item, event = chunk)
        if (!is.null(key)) streamed_item_keys <- c(streamed_item_keys, key)
      }
      content <- utils::getFromNamespace("stream_content", "ellmer")(
        provider,
        chunk
      )
      if (!is.null(content)) {
        emitted <- codex_emit_stream_content(content, emit, yield_as_content)
        if (!is.null(emitted)) coro::yield(emitted)
        accumulator$update_turn(content)
        streamed_text <- streamed_text || inherits(content, "ellmer::ContentText")
        any_text <- any_text ||
          !utils::getFromNamespace("is_tool_request", "ellmer")(content)
      }
      result <- utils::getFromNamespace("stream_merge_chunks", "ellmer")(
        provider,
        result,
        chunk
      )
    }

    if (!isTRUE(controller$cancelled)) {
      utils::getFromNamespace("record_chat_otel_span_status", "ellmer")(
        chat_span,
        provider,
        result
      )
      turn <- accumulator$complete_turn(result, type = type)
      completed <- TRUE
      utils::getFromNamespace("record_chat_otel_span_output", "ellmer")(
        chat_span,
        turn
      )
      if (!is.null(turn) && !inherits(turn, "ellmer::AssistantPartialTurn")) {
        terminal_contents <- codex_terminal_stream_contents(
          result,
          streamed_item_keys = unique(streamed_item_keys),
          streamed_text = streamed_text
        )
        for (content in terminal_contents) {
          emitted <- codex_emit_stream_content(content, emit, yield_as_content)
          if (!is.null(emitted)) coro::yield(emitted)
          any_text <- any_text || inherits(content, "ellmer::ContentText")
        }
        if (any_text) {
          emit("\n")
          if (isTRUE(yield_as_content)) {
            coro::yield(ellmer::ContentText("\n"))
          } else {
            coro::yield("\n")
          }
        }
        if (identical(echo, "all")) {
          utils::getFromNamespace("echo_non_text_contents", "ellmer")(turn)
        }
      }
    }
  })()
}

codex_submit_turns_async <- function(
  self,
  private,
  user_turn,
  type = NULL,
  stream = FALSE,
  echo = "none",
  yield_as_content = FALSE,
  controller = NULL,
  otel_span = NULL
) {
  if (is.null(controller)) controller <- ellmer::stream_controller()
  provider <- private$provider
  tools <- if (is.null(type)) private$tools else NULL
  accumulator_class <- utils::getFromNamespace("TurnAccumulator", "ellmer")
  if (identical(echo, "all")) {
    utils::getFromNamespace("cat_line", "ellmer")(format(user_turn), prefix = "> ")
  }

  coro::async_generator(function() {
    request_turns <- c(private$.turns, list(user_turn))
    otel_input <- utils::getFromNamespace("otel_chat_input", "ellmer")(
      private,
      user_turn
    )
    chat_span <- utils::getFromNamespace("local_chat_otel_span", "ellmer")(
      provider,
      turns = otel_input$turns,
      system_prompt = otel_input$system_prompt,
      parent = otel_span
    )
    accumulator <- accumulator_class$new(self, private, controller)
    accumulator$begin_turn(user_turn)
    completed <- FALSE
    on.exit({
      if (!isTRUE(completed)) accumulator$finalize_turn()
    }, add = TRUE)

    request <- utils::getFromNamespace("chat_perform", "ellmer")(
      provider = provider,
      mode = "async-stream",
      turns = request_turns,
      tools = tools,
      type = type,
      otel_span = chat_span,
      controller = controller
    )

    emit <- utils::getFromNamespace("emitter", "ellmer")(echo)
    any_text <- FALSE
    streamed_item_keys <- character()
    streamed_text <- FALSE
    result <- NULL
    for (chunk in coro::await_each(request)) {
      if (identical(codex_stream_event_type(chunk), "response.output_item.done")) {
        item <- codex_stream_event_item(chunk)
        key <- codex_stream_item_key(item, event = chunk)
        if (!is.null(key)) streamed_item_keys <- c(streamed_item_keys, key)
      }
      content <- utils::getFromNamespace("stream_content", "ellmer")(
        provider,
        chunk
      )
      if (!is.null(content)) {
        emitted <- codex_emit_stream_content(content, emit, yield_as_content)
        if (!is.null(emitted)) coro::yield(emitted)
        accumulator$update_turn(content)
        streamed_text <- streamed_text || inherits(content, "ellmer::ContentText")
        any_text <- any_text ||
          !utils::getFromNamespace("is_tool_request", "ellmer")(content)
      }
      result <- utils::getFromNamespace("stream_merge_chunks", "ellmer")(
        provider,
        result,
        chunk
      )
    }

    if (!isTRUE(controller$cancelled)) {
      utils::getFromNamespace("record_chat_otel_span_status", "ellmer")(
        chat_span,
        provider,
        result
      )
      turn <- accumulator$complete_turn(result, type = type)
      completed <- TRUE
      utils::getFromNamespace("record_chat_otel_span_output", "ellmer")(
        chat_span,
        turn
      )
      if (!is.null(turn) && !inherits(turn, "ellmer::AssistantPartialTurn")) {
        terminal_contents <- codex_terminal_stream_contents(
          result,
          streamed_item_keys = unique(streamed_item_keys),
          streamed_text = streamed_text
        )
        for (content in terminal_contents) {
          emitted <- codex_emit_stream_content(content, emit, yield_as_content)
          if (!is.null(emitted)) coro::yield(emitted)
          any_text <- any_text || inherits(content, "ellmer::ContentText")
        }
        if (any_text) {
          emit("\n")
          if (isTRUE(yield_as_content)) {
            coro::yield(ellmer::ContentText("\n"))
          } else {
            coro::yield("\n")
          }
        }
        if (identical(echo, "all")) {
          utils::getFromNamespace("echo_non_text_contents", "ellmer")(turn)
        }
      }
    }
  })()
}

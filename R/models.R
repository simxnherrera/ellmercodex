# Account-specific model discovery through the observed Codex catalog endpoint.

codex_models_client_version_default <- function() "0.149.0"

codex_models_client_version <- function() {
  override <- Sys.getenv("ELLMERCODEX_CLIENT_VERSION", unset = "")
  if (is.character(override) && length(override) == 1L &&
      !is.na(override) && nzchar(override)) {
    return(override)
  }

  # Keep model discovery package-native. This is the last verified native
  # client compatibility value; updating it is a package maintenance task, not
  # a runtime lookup of another executable.
  codex_models_client_version_default()
}

codex_models_unsupported_reason <- function() {
  paste(
    "The Codex model catalog could not be used. The account-specific",
    "catalog endpoint is an undocumented compatibility surface and may be",
    "unavailable or change without notice."
  )
}

codex_models_empty <- function(supported = TRUE, reason = NULL) {
  result <- data.frame(
    id = character(),
    owned_by = character(),
    display_name = character(),
    description = character(),
    default_reasoning_effort = character(),
    supported_reasoning_efforts = I(list()),
    supported_in_api = logical(),
    priority = integer(),
    default_service_tier = character(),
    service_tiers = I(list()),
    stringsAsFactors = FALSE
  )
  class(result) <- c("codex_models", "data.frame")
  attr(result, "supported") <- isTRUE(supported)
  if (!is.null(reason)) attr(result, "reason") <- reason
  result
}

codex_model_character <- function(value, default = "") {
  if (is.character(value) && length(value) == 1L && !is.na(value)) {
    value
  } else {
    default
  }
}

codex_model_effort_names <- function(value) {
  if (is.character(value)) {
    return(value[!is.na(value) & nzchar(value)])
  }
  if (!is.list(value)) {
    return(character())
  }
  efforts <- vapply(
    value,
    function(item) {
      if (is.list(item)) {
        return(codex_model_character(item$effort))
      }
      codex_model_character(item)
    },
    character(1)
  )
  unique(efforts[nzchar(efforts)])
}

codex_model_service_tiers <- function(value) {
  if (is.character(value)) {
    return(value[!is.na(value) & nzchar(value)])
  }
  if (!is.list(value)) {
    return(character())
  }
  tiers <- vapply(
    value,
    function(item) {
      if (is.list(item)) {
        return(codex_model_character(item$id %||% item$name))
      }
      codex_model_character(item)
    },
    character(1)
  )
  unique(tiers[nzchar(tiers)])
}

codex_model_record <- function(model) {
  if (!is.list(model)) {
    return(NULL)
  }
  id <- codex_model_character(model$slug %||% model$id)
  if (!nzchar(id)) {
    return(NULL)
  }

  default_effort <- model$default_reasoning_level %||%
    model$default_reasoning_effort
  supported <- model$supported_reasoning_levels %||%
    model$supported_reasoning_efforts
  tiers <- model$service_tiers %||% model$additional_speed_tiers
  priority <- suppressWarnings(as.integer(model$priority %||% NA_integer_))
  if (length(priority) != 1L || is.na(priority)) priority <- NA_integer_

  list(
    id = id,
    owned_by = codex_model_character(model$owned_by, "codex"),
    display_name = codex_model_character(model$display_name, id),
    description = codex_model_character(model$description),
    default_reasoning_effort = codex_model_character(default_effort),
    supported_reasoning_efforts = codex_model_effort_names(supported),
    supported_in_api = isTRUE(model$supported_in_api %||% TRUE),
    priority = priority,
    default_service_tier = codex_model_character(model$default_service_tier),
    service_tiers = codex_model_service_tiers(tiers)
  )
}

codex_models_result <- function(records, source = "codex") {
  if (!is.list(records) || length(records) == 0L) {
    result <- codex_models_empty(supported = TRUE)
  } else {
    records <- Filter(Negate(is.null), records)
    if (length(records) == 0L) {
      result <- codex_models_empty(supported = TRUE)
    } else {
      result <- data.frame(
        id = vapply(records, `[[`, character(1), "id"),
        owned_by = vapply(records, `[[`, character(1), "owned_by"),
        display_name = vapply(records, `[[`, character(1), "display_name"),
        description = vapply(records, `[[`, character(1), "description"),
        default_reasoning_effort = vapply(
          records, `[[`, character(1), "default_reasoning_effort"
        ),
        supported_reasoning_efforts = I(lapply(
          records, `[[`, "supported_reasoning_efforts"
        )),
        supported_in_api = vapply(records, `[[`, logical(1), "supported_in_api"),
        priority = vapply(records, `[[`, integer(1), "priority"),
        default_service_tier = vapply(
          records, `[[`, character(1), "default_service_tier"
        ),
        service_tiers = I(lapply(records, `[[`, "service_tiers")),
        stringsAsFactors = FALSE
      )
      class(result) <- c("codex_models", "data.frame")
      attr(result, "supported") <- TRUE
    }
  }
  attr(result, "source") <- source
  result
}

codex_models_parse <- function(value) {
  models <- if (is.list(value)) value$models else NULL
  # Accept the standard OpenAI `/models` envelope as a compatibility fallback;
  # the Codex endpoint currently uses `models`.
  if (is.null(models) && is.list(value)) models <- value$data
  if (!is.list(models)) {
    rlang::abort(
      "The Codex model catalog did not match the expected response shape.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }
  codex_models_result(lapply(models, codex_model_record))
}

codex_model_selection_abort <- function(message, parent = NULL) {
  rlang::abort(
    message,
    class = "codex_model_selection_error",
    parent = parent
  )
}

codex_model_catalog_for_selection <- function(auth) {
  tryCatch(
    codex_models(auth = auth),
    error = function(error) {
      codex_model_selection_abort(
        paste(
          "The account-specific Codex model catalog could not be discovered.",
          "chat_codex() cannot safely choose a default or validate reasoning",
          "effort without it. Run codex_models() to inspect the failure, or",
          "pass an explicitly verified model and omit effort."
        ),
        parent = error
      )
    }
  )
}

codex_model_catalog_row <- function(models, model) {
  matches <- which(identical(models$id, model) | models$id == model)
  if (length(matches) != 1L) {
    codex_model_selection_abort(
      paste(
        "The selected Codex model", shQuote(model),
        "is not present exactly once in the current account catalog.",
        "Run codex_models() and choose an advertised model."
      )
    )
  }
  models[matches[[1L]], , drop = FALSE]
}

codex_model_catalog_default <- function(models) {
  eligible <- which(!is.na(models$supported_in_api) & models$supported_in_api)
  if (length(eligible) == 0L) {
    codex_model_selection_abort(
      paste(
        "The account-specific Codex catalog returned no models marked as",
        "usable. Confirm the subscription and workspace, then retry",
        "codex_models(); no model was selected silently."
      )
    )
  }

  priorities <- models$priority[eligible]
  # The catalog's lowest advertised priority is the deterministic default;
  # when priority is absent, retain the service's catalog order.
  order_index <- order(
    is.na(priorities),
    priorities,
    eligible,
    na.last = TRUE
  )
  models$id[[eligible[[order_index[[1L]]]]]]
}

codex_validate_model_effort <- function(models, model, effort) {
  if (is.null(effort)) return(invisible(NULL))
  row <- codex_model_catalog_row(models, model)
  supported <- row$supported_reasoning_efforts[[1L]]
  if (!is.character(supported)) supported <- character()
  if (!effort %in% supported) {
    advertised <- if (length(supported)) paste(supported, collapse = ", ") else "none"
    codex_model_selection_abort(
      paste(
        "Reasoning effort", shQuote(effort), "is not advertised for Codex model",
        shQuote(model), ". Supported values:", advertised,
        ". Use codex_models() to choose a compatible effort."
      )
    )
  }
  invisible(effort)
}

codex_select_model <- function(auth, model = NULL, effort = NULL) {
  if (is.null(model)) model <- codex_default_model()
  catalog <- NULL
  if (is.null(model) || !is.null(effort)) {
    catalog <- codex_model_catalog_for_selection(auth)
  }
  if (is.null(model)) {
    if (nrow(catalog) == 0L) {
      codex_model_selection_abort(
        paste(
          "The account-specific Codex model catalog is empty, so",
          "chat_codex(model = NULL) cannot choose a model.",
          "Authenticate again or inspect codex_models(); pass an explicit",
          "model only after verifying that the account can use it."
        )
      )
    }
    model <- codex_model_catalog_default(catalog)
  }
  if (!is.null(effort)) codex_validate_model_effort(catalog, model, effort)
  list(model = model, catalog = catalog)
}

codex_models_request_headers <- function(auth) {
  headers <- codex_request_headers(auth)
  headers[["Accept"]] <- "application/json"
  headers
}

#' List models available to the authenticated Codex account.
#'
#' This makes one authenticated request to the observed Codex model catalog
#' endpoint. The returned rows include each model's advertised reasoning effort
#' levels, so callers can select an effort without copying a stale catalog into
#' this package. Availability is account- and workspace-specific.
#'
#' @param auth Optional package credential. If omitted, the current session or
#'   package-owned credential is loaded and refreshed as needed.
#' @param client_version Optional client-version query value. If omitted or
#'   `NULL`, the package's verified compatibility value is used;
#'   `ELLMERCODEX_CLIENT_VERSION` can override it.
#' @return A `codex_models` data frame with one row per catalog model. Its
#'   columns are:
#'     \item{`id`}{The model identifier accepted by \link{chat_codex}.}
#'     \item{`owned_by`}{The service or owner label advertised by the catalog.}
#'     \item{`display_name`}{A human-readable model name.}
#'     \item{`description`}{The catalog description, when supplied.}
#'     \item{`default_reasoning_effort`}{The advertised default effort.}
#'     \item{`supported_reasoning_efforts`}{A list-column of effort names.}
#'     \item{`supported_in_api`}{Whether the catalog marks the model as API-supported.}
#'     \item{`priority`}{The catalog priority, when supplied.}
#'     \item{`default_service_tier`}{The advertised default service tier.}
#'     \item{`service_tiers`}{A list-column of advertised service tiers.}
#'   The `supported` and `source` attributes describe the catalog result.
#' @section Conditions:
#' Missing credentials signal `codex_auth_missing`; HTTP and protocol failures
#' use the same sanitized transport conditions as generation requests.
#' @note The catalog is account- and workspace-specific and is queried at
#'   call time. Cache or select a model explicitly if a reproducible workflow
#'   must not change when the account's catalog changes.
#' @examplesIf interactive()
#' models <- codex_models()
#' models[c("id", "default_reasoning_effort", "supported_reasoning_efforts")]
#' @export
codex_models <- function(
  auth = NULL,
  client_version = codex_models_client_version()
) {
  if (!is.null(auth) && !inherits(auth, "codex_auth")) {
    rlang::abort(
      "`auth` must be a Codex credential or NULL.",
      class = "codex_auth_argument_error",
      parent = NULL
    )
  }
  if (!is.null(client_version) &&
      (!is.character(client_version) || length(client_version) != 1L ||
       is.na(client_version) || !nzchar(client_version))) {
    rlang::abort(
      "`client_version` must be NULL or one non-empty string.",
      class = "codex_auth_argument_error",
      parent = NULL
    )
  }
  if (is.null(client_version)) {
    client_version <- codex_models_client_version()
  }

  explicit_auth <- !is.null(auth)
  if (is.null(auth)) auth <- codex_auth()
  if (isTRUE(codex_token_expired(auth))) {
    auth <- codex_refresh(auth, persist = !explicit_auth)
  }

  endpoint <- codex_models_endpoint()
  if (!is.character(endpoint) || length(endpoint) != 1L || is.na(endpoint) ||
      !grepl("^https://", endpoint, perl = TRUE)) {
    rlang::abort(
      "The Codex model catalog endpoint must be an HTTPS URL.",
      class = "codex_request_error",
      parent = NULL
    )
  }
  endpoint <- httr2::url_modify(
    endpoint,
    query = list(client_version = client_version)
  )

  request <- httr2::request(endpoint) |>
    httr2::req_headers(!!!codex_models_request_headers(auth)) |>
    httr2::req_timeout(30) |>
    httr2::req_error(is_error = function(response) FALSE)
  response <- tryCatch(
    httr2::req_perform(request),
    error = function(error) {
      rlang::abort(
        "The Codex model catalog request failed because of an ordinary network error.",
        class = "codex_network_error",
        parent = NULL
      )
    }
  )
  status <- tryCatch(httr2::resp_status(response), error = function(error) NA_integer_)
  if (is.na(status) || status < 200L || status >= 300L) {
    codex_abort_response(response)
  }

  value <- tryCatch(
    httr2::resp_body_json(response, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (!is.list(value)) {
    rlang::abort(
      "The Codex model catalog response was not valid JSON.",
      class = "codex_protocol_changed_error",
      parent = NULL
    )
  }
  codex_models_parse(value)
}

#' @export
print.codex_models <- function(x, ...) {
  if (nrow(x) == 0L) {
    cat("No Codex models were returned.\n")
    return(invisible(x))
  }
  display <- x[intersect(
    c("id", "display_name", "default_reasoning_effort"),
    names(x)
  )]
  if ("supported_reasoning_efforts" %in% names(x)) {
    display$supported_reasoning_efforts <- vapply(
      x$supported_reasoning_efforts,
      function(value) paste(value, collapse = ", "),
      character(1)
    )
  }
  print.data.frame(display, ...)
  invisible(x)
}

# Retained for callers that used the first release's diagnostic helper.
#' @export
#' @keywords internal
print.codex_models_unsupported <- function(x, ...) {
  reason <- attr(x, "reason") %||% codex_models_unsupported_reason()
  cat("No Codex model catalog available. ", reason, "\n", sep = "")
  invisible(x)
}

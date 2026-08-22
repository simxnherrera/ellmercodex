# ellmer 0.4.2 compatibility inventory

This inventory is derived from the installed `ellmer` 0.4.2 package, not from
an assumed or reduced interface. `chat_codex()` returns the actual ellmer R6
`Chat` object (`class(chat) == c("Chat", "R6")`) and keeps all of its public
methods and public method signatures.

## Chat methods

| Method | Installed 0.4.2 signature | Compatibility implementation |
|---|---|---|
| `initialize` | `function(provider, system_prompt = NULL, echo = "none")` | ellmer `Chat` constructor, with the version-gated `CodexProvider` |
| `get_turns` | `function(include_system_prompt = FALSE)` | ellmer Chat state; system-turn filtering preserved |
| `set_turns` | `function(value)` | ellmer validation and state replacement |
| `add_turn` | `function(user, assistant, log_tokens = TRUE)` | ellmer state and token logging |
| `get_system_prompt` | `function()` | ellmer Chat state |
| `get_model` | `function()` | provider model field |
| `set_model` | `function(model)` | provider model mutation |
| `set_system_prompt` | `function(value)` | ellmer Chat state |
| `get_tokens` | `function(include_system_prompt = deprecated())` | ellmer aggregation over normalized turns |
| `get_cost` | `function(include = c("all", "last"))` | ellmer aggregation over normalized turns; unknown Codex prices remain typed `NA` rather than fabricated |
| `last_turn` | `function(role = c("assistant", "user", "system"))` | ellmer Chat state |
| `chat` | `function(..., echo = NULL)` | ellmer public method plus the version-gated private tool loop; Codex transport always uses SSE internally |
| `chat_structured` | `function(..., type, echo = "none", convert = TRUE)` | ellmer structured lifecycle; Codex Responses schema body and `ContentJson` conversion |
| `chat_structured_async` | `function(..., type, echo = "none", convert = TRUE)` | ellmer async structured lifecycle over the Codex async SSE transport |
| `chat_async` | `function(..., tool_mode = c("concurrent", "sequential"))` | ellmer async tool helpers plus the version-gated loop and promise return shape |
| `stream` | `function(..., stream = c("text", "content"), controller = NULL)` | ellmer stream generator; text/content selection and controller cancellation preserved |
| `stream_async` | `function(..., tool_mode = c("concurrent", "sequential"), stream = c("text", "content"), controller = NULL)` | ellmer async generator; tool mode and cancellation preserved |
| `register_tool` | `function(tool)` | ellmer `ToolDef` validation and registration |
| `register_tools` | `function(tools)` | ellmer tool registration |
| `get_provider` | `function()` | returns the version-gated `CodexProvider` |
| `get_tools` | `function()` | ellmer Chat state |
| `set_tools` | `function(tools)` | ellmer Chat state and validation |
| `on_tool_request` | `function(callback)` | ellmer callback manager and removal function |
| `on_tool_result` | `function(callback)` | ellmer callback manager and removal function |
| `clone` | `function(deep = FALSE)` | inherited R6 clone; private execution methods are installed with the Chat enclosing environment so cloned methods point to the clone, never the original |

There are no public Chat fields in the installed object. The relevant private
fields are `provider`, `.turns`, `echo`, `tools`, the two callback managers,
and ellmer's private chat/tool lifecycle methods. The compatibility layer
rebinds only `chat_impl`, `chat_impl_async`, `submit_turns`, and
`submit_turns_async`, in one version-gated module. The public methods remain
ellmer's own methods.

The inherited/ambient public behavior is also unchanged: `clone(deep = FALSE)`
is R6 behavior, `print(chat)` uses ellmer's `print.Chat` summary, and
`format(chat)` uses the inherited R6 formatter.

## Return shapes and state transitions

The following are the observed 0.4.2 behaviors preserved by the adapter.

| Method | Return shape and side effect |
|---|---|
| `initialize` | Initializes the provider, echo mode, callback managers, and optional system turn; returns the initialized R6 object through normal R6 construction. |
| `get_turns` | Returns a list of `Turn` objects; omits the leading system turn by default and includes it when requested; does not mutate state. |
| `set_turns` | Normalizes and replaces Chat history, preserving the system prompt rules; returns the Chat invisibly. |
| `add_turn` | Validates and appends one user/assistant pair, optionally logs assistant usage, and returns the Chat invisibly. |
| `get_system_prompt` | Returns one character string or `NULL`; does not mutate state. |
| `get_model` | Returns the provider model string; does not mutate state. |
| `set_model` | Validates and mutates the provider model; returns the Chat invisibly. |
| `set_system_prompt` | Removes/replaces the leading system turn or adds one; returns the Chat invisibly. |
| `get_tokens` | Returns an ellmer tibble with input, output, cached-input, cost, and input-preview columns for complete assistant turns; excludes partial turns and optionally excludes the system turn. |
| `get_cost` | Returns an `ellmer_dollars` scalar for all or the last complete assistant turn; returns zero when no complete turn exists. |
| `last_turn` | Returns the last matching `Turn` or `NULL`; does not mutate state. |
| `chat` | Returns an `ellmer_output` string, or invisibly returns it when echoing; appends user/partial/assistant turns, executes all tool rounds, invokes callbacks, and completes dangling requests first. |
| `chat_structured` | Returns the value converted from the requested ellmer type; appends the normalized `ContentJson` assistant turn and follows ellmer's structured-output tool policy. |
| `chat_structured_async` | Returns a promise resolving to the converted typed value; performs the same state transition asynchronously. |
| `chat_async` | Returns a promise resolving to assistant text; uses ellmer's sequential/concurrent async tool loop and updates history before settlement. |
| `stream` | Returns a coro generator yielding text strings or ordered Content objects; turns become partial during iteration, complete on terminal response, or retain an interrupted partial turn on cancellation. |
| `stream_async` | Returns an async coro generator with the same content/state semantics and async tool mode selection. |
| `register_tool` | Validates/replaces one named `ToolDef`, mutates the tool registry, and returns the Chat invisibly. |
| `register_tools` | Validates and registers a list of `ToolDef` objects, mutating the registry and returning the Chat invisibly. |
| `get_provider` | Returns the `CodexProvider` S7 object; does not mutate state. |
| `get_tools` | Returns the named registered-tool list; does not mutate state. |
| `set_tools` | Validates and replaces the tool registry; returns the Chat invisibly. |
| `on_tool_request` | Registers a callback and returns ellmer's callback-removal function. |
| `on_tool_result` | Registers a callback and returns ellmer's callback-removal function. |
| `clone` | Returns an independent R6 Chat with copied history/registrations and clone-remapped method environments; the source Chat is not mutated. |

## State and conversion guarantees

- Each request begins with ellmer's `complete_dangling_tool_requests()` path.
- ellmer owns turns, partial turns, callbacks, tool-loop rounds, cancellation,
  echo selection, async promises/generators, cloning, token aggregation, and
  cost aggregation.
- The Codex provider forces `stream = TRUE` in every Chat request, including
  sync, async, structured, and tool rounds, because the supported subscription
  endpoint rejects non-streaming requests.
- SSE merge state keeps the event order of text segments, function calls,
  reasoning, images, PDFs, and other output items. Terminal output fills in
  omitted items without moving streamed text across a tool call.
- Usage is normalized into ellmer's input/output/cached-input token shape;
  duration and finish metadata are written by `TurnAccumulator` and the
  provider converter. A cost is computed when ellmer has a matching price and
  is typed `NA` when the account-specific Codex model has no installed price.
- Unknown Responses output items are retained as `ContentJson` with the full
  original item instead of being silently dropped.

## Public ellmer helpers outside Chat

The installed package also exports `parallel_chat()`,
`parallel_chat_text()`, `parallel_chat_structured()`, `batch_chat()`,
`batch_chat_text()`, `batch_chat_structured()`, and
`batch_chat_completed()`. They are not Chat methods, but are part of the
ellmer surface and were audited.

In ellmer 0.4.2 these helpers construct non-streaming requests and, for batch,
use the OpenAI Files/Batches API. The Codex subscription endpoint accepts only
the stream-only Responses transport and does not expose that batch API. The
parallel helpers fail with `codex_ellmer_parallel_batch_blocker`; the batch
helpers stop in ellmer's generic provider capability check with
`Batch requests are not currently supported by this provider.` Both paths stop
before a request is sent, and batch helpers stop before creating a state file.
This is an explicit stable-core boundary, not a no-op or a false-success
fallback. The package's stable contract covers the public `Chat` object above;
it does not claim compatibility with these separately exported parallel/batch
helpers.

| Helper | Installed signature | Status |
|---|---|---|
| `parallel_chat` | `function(chat, prompts, max_active = 10, rpm = 500, on_error = c("return", "continue", "stop"))` | Explicit blocker before request construction |
| `parallel_chat_text` | Same as `parallel_chat` | Explicit blocker before request construction |
| `parallel_chat_structured` | `function(chat, prompts, type, convert = TRUE, include_tokens = FALSE, include_cost = FALSE, max_active = 10, rpm = 500, on_error = c("return", "continue", "stop"))` | Explicit blocker before request construction |
| `batch_chat` | `function(chat, prompts, path, wait = TRUE, ignore_hash = FALSE)` | Ellmer generic unsupported-provider error before state-file creation |
| `batch_chat_text` | Same as `batch_chat` | Ellmer generic unsupported-provider error before state-file creation |
| `batch_chat_structured` | `function(chat, prompts, path, type, wait = TRUE, ignore_hash = FALSE, convert = TRUE, include_tokens = FALSE, include_cost = FALSE)` | Ellmer generic unsupported-provider error before state-file creation |
| `batch_chat_completed` | `function(chat, prompts, path)` | Ellmer generic unsupported-provider error before state-file creation |

Provider-native helper declarations that are accepted by ellmer are passed
through the parent OpenAI Responses serializer. A returned Responses item
that has no dedicated ellmer Content class is retained as `ContentJson`, with
its exact provider payload available in the assistant turn.

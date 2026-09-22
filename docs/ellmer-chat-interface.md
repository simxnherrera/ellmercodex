# ellmer Chat compatibility (0.5.0 or later)

`chat_codex()` returns ellmer's own `Chat` object. The minimum supported version
is 0.5.0, with no upper version limit. The adapter checks required exported
symbols, Provider generic signatures, and Chat method and private-state
contracts before it can send a Codex request. An incompatible future ellmer
release raises `codex_ellmer_compatibility_error` with the missing contract;
it is not automatically certified by the open version range.

## Supported Chat operations

| Operation | Behavior with Codex |
|---|---|
| `chat()`, `chat_async()` | Text, history and multi-round function tools over the streaming Responses endpoint. |
| `chat_structured()`, `chat_structured_async()` | Native JSON schema output and ellmer type conversion; registered tools are disabled for that request. |
| `stream()`, `stream_async()` | Text or Content chunks, controller cancellation and partial turns. Structured streaming passes the `type` argument to the request. |
| `register_tool()`, `register_tools()`, `get_tools()`, `set_tools()` | Ellmer tool definitions and registry. Tool functions should return strings, JSON, Content objects, or lists of Content objects; convert other complex values to JSON explicitly. |
| `on_tool_request()`, `on_tool_result()`, `on_request_start()`, `on_request_end()` | Ellmer callbacks, including a callback for every Codex request in a tool loop. |
| `get_turns()`, `set_turns()`, `add_turn()`, `get_rounds()`, `last_turn()`, `last_round()` | Ellmer history and round views. |
| `get_model()`, `set_model()`, `get_model_object()`, `get_provider()` | The model name, parameters and extra arguments live on ellmer's `Model`; provider settings and credentials live on `CodexProvider`. |
| `get_tokens()`, `get_cost()` | Aggregation of reported usage. Unknown usage and prices remain unknown. |
| `clone()` | An independent R6 Chat; patched private methods bind to the clone. |

Image and PDF content is serialized through ellmer's OpenAI Responses
serializer. Unrecognized response items remain available as `ContentJson`.
Codex's streaming endpoint is used even for `$chat()` and
`$chat_structured()`. A non-streaming request is blocked before transmission.

## Unavailable operations

| Operation | Result |
|---|---|
| `token_count()` and related provider token counting | `codex_ellmer_compatibility_error`; the Codex subscription transport has no supported token-count endpoint. |
| `file_upload()`, `file_list()`, `file_get()`, `file_download()`, `file_delete()` | `codex_ellmer_compatibility_error`; the Codex subscription transport does not provide the provider file API. Inline image and PDF content remains supported. |
| `parallel_chat*()` | A typed blocker before a non-streaming request. |
| `batch_chat*()` | Ellmer's unsupported-provider error before batch state creation. |

The boundary depends on ellmer's private Chat execution methods and an
undocumented Codex transport. CI runs the offline fixtures against ellmer
0.5.0 and the latest published release, with no authentication or real
requests.

# ellmercodex 0.1.1

* Added authenticated Codex model discovery with per-model reasoning-effort
  metadata; the package no longer invents a static model catalog.
* Added `effort`, ellmer `params()`, and `api_args` support to `chat_codex()`.
  Reasoning effort is forwarded using ellmer's Responses-compatible mapping.
* Added streamed structured output through `Chat$chat_structured()`, including
  repair of the terminal assistant turn into ellmer `ContentJson`.
* Added first-class ellmer function-tool calling through `chat_codex()`,
  including fragmented Responses arguments, multiple/sequential calls,
  local tool errors/rejections, streaming content, and tool-preserving
  conversation history. Structured-output requests intentionally continue to
  disable registered tools, matching ellmer.
* Added offline fixtures for model discovery, effort propagation, and
  structured-output conversion; updated the experimental compatibility notes.

# ellmercodex 0.1.0

* Converted the validated proof of concept into an installable R package with
  six exported functions, offline examples, a getting-started vignette, and a
  manual opt-in compatibility check.
* Added the explicitly opt-in `chat_codex()` wrapper around ellmer's exported
  `chat_openai()` seam. The compatibility layer is tested against ellmer
  0.4.x starting at 0.4.2, buffers streamed text, and repairs the terminal
  assistant turn used for multi-turn history.
* Added package-scoped OS-keyring persistence, an explicitly enabled encrypted
  file fallback, refresh-token rotation, logout, and redacted diagnostics.
* Added fixture-based request, SSE, credential, authentication, diagnostic,
  package-contract, and ellmer compatibility tests that do not use the network
  or inspect user credentials.
* Documented that the observed subscription OAuth and direct Responses
  transport are experimental, undocumented compatibility behavior. This
  package is not affiliated with or endorsed by OpenAI.

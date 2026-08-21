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

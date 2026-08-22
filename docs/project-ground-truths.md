# ellmercodex project ground truths

This document records the product intent repeatedly stated by the project owner across the project's Codex task history. It is a requirements baseline, not a description of the current implementation. When an early milestone deliberately deferred a feature and a later task explicitly required it, the later requirement controls the long-term product while the earlier statement remains relevant only to that milestone.

## Product identity

`ellmercodex` is an independent companion package to `ellmer`. Its purpose is to let an R user use Codex access associated with an eligible ChatGPT subscription through a normal `ellmer` Chat interface.

The defining user experience is:

```r
library(ellmercodex)

codex_login()
chat <- chat_codex(model = NULL)
chat$chat("Explain this regression model.")
```

The package is not meant to be a standalone coding agent, a replacement for `ellmer`, or an R wrapper around the Codex CLI. Pi, OpenCode, and similar clients are references for direct subscription authentication and transport, not the architecture presented to R users.

## Non-negotiable runtime architecture

Normal package operation must work without:

- an OpenAI API key;
- the `codex` CLI executable;
- `codex app-server`;
- Node, Python, or Rust;
- a local proxy.

Authentication, credential refresh, model discovery, requests, streaming, and Chat operation must be implemented by the package itself, in R wherever practical. The Codex CLI may be inspected as a development reference, but it is not a runtime dependency or fallback.

The architectural seam presented to users is the public `ellmer` Chat interface:

```text
R user -> ellmer Chat interface -> ellmercodex adapter -> Codex subscription service
```

Codex-specific complexity belongs in a small number of internal modules: authentication and credential refresh, transport, request/response conversion, streaming and content normalization, tool lifecycle, model discovery, and version-gated `ellmer` compatibility.

## Authentication and account boundaries

- Login is an explicit browser OAuth flow initiated only by `codex_login()` and modeled on the user experience of Pi-style login.
- Package loading, examples, tests, and checks must never initiate authentication.
- Credentials must be stored securely in the OS credential store where practical, with any fallback confined to package-specific user storage.
- Refresh and refresh-token rotation must work transparently and persist safely.
- Injected credentials used by tests or callers must remain usable throughout sync, async, and tool paths; code must not unexpectedly re-enter the keyring.
- The package must never read `~/.codex/auth.json`, scrape another application's credentials, impersonate an approved client, expose secrets, spoof entitlement, or bypass subscription/rate limits.
- The package must clearly state that it is independent of OpenAI and Posit and that the direct subscription protocol is undocumented or unstable where that remains true.

## Public package contract

The deliberately small top-level package API is:

- `codex_login()`
- `codex_logout()`
- `codex_account()`
- `codex_models()`
- `codex_available()`
- `chat_codex()`

That small exported API must not imply a reduced Chat object. `chat_codex()` should return an ordinary, usable `ellmer` Chat whose supported behavior is governed by the chosen supported `ellmer` version.

## `ellmer` compatibility ground truth

The package should keep `ellmer` as the source of truth for public Chat semantics and state wherever possible. Users should not need a parallel ellmercodex-specific conversation API.

The required model-facing surface includes:

- ordinary and multi-turn chat;
- text streaming;
- sync and async chat and streaming;
- structured output;
- user-defined `ellmer::tool()` registration and complete multi-round tool loops;
- sequential and concurrent async tool execution where `ellmer` supports them;
- tool callbacks, failures, recovery, correct turn ordering, and dangling-tool handling;
- image/PDF inputs and ordered rich response content;
- cancellation;
- cloning without closures or mutable state pointing back to the original Chat;
- getting, setting, and preserving turns/history;
- compatible echo behavior;
- usage, cost, duration, finish, and response metadata to the extent the Codex transport supplies them;
- model and provider configuration, including reasoning-effort selection;
- inherited public Chat behavior that callers reasonably expect.

Content ordering is part of correctness. Sequences such as text -> tool -> text and text -> image -> text must not be flattened, duplicated, reordered, or silently discarded.

Private `ellmer` internals may be used only when no public extension seam can provide the required behavior. Any such use must be isolated in one compatibility layer, guarded to an exact supported `ellmer` range, and documented as maintenance risk.

The owner later accepted a practical stable-release definition of **stable core Chat support with explicitly unsupported parallel/batch helpers**. Therefore `parallel_chat()` and `batch_chat()` need not block that release if they are genuinely outside the core Chat contract and are clearly reported as unsupported. This exception does not authorize removing or silently degrading tools or other model-facing Chat capabilities.

If the Codex subscription service cannot supply a capability that an API-key provider can supply, the package must expose and document the limitation honestly. It must not fabricate metadata, simulate tools through prompting, silently no-op, or claim full support.

## Models and reasoning effort

- `codex_models()` is a real user requirement and should return the models actually usable by the logged-in account whenever reliable discovery is possible.
- An empty result is not an acceptable steady-state experience when the account can chat with Codex models.
- Dynamic account-specific discovery is preferred. If a fallback catalog is unavoidable, it must be centralized, evidence-based, and explicitly identified as a fallback rather than silently presented as live discovery.
- `chat_codex(model = NULL)` should choose an appropriate current default rather than scatter a hard-coded model through the package.
- Reasoning effort must be selectable through the package in a way compatible with both Codex's supported values and `ellmer`'s parameter conventions.

## Quality, testing, and release expectations

- Offline tests must cover authentication state, request serialization, SSE parsing, tools, rich content, async behavior, errors, and compatibility without credentials, browsers, or network access.
- Live tests must be opt-in and excluded from CRAN and ordinary CI.
- Offline fixtures and mocked tests are necessary but not sufficient for a release that changes live behavior. The owner explicitly requires logging in and exercising real `chat_codex()` use cases when validating authentication, model discovery, model selection, reasoning effort, streaming, duplication fixes, and other end-to-end behavior.
- A response must appear exactly once. Duplicate console output or duplicated return/history content is a release-blocking user-visible defect.
- The package should be documented and checked to CRAN standards, including examples that cannot trigger OAuth or network access.
- Until it is actually on CRAN, installation instructions should use the real GitHub route (the owner selected `pak`) and the README should focus on package users rather than internal development/offline-test details.
- Releases should include the relevant tests and checks, a clean review of the diff, GitHub publication, and honest documentation of experimental protocol risk.
- The long-term goal is a CRAN-publishable package, even while GitHub releases are the available distribution channel.

## Explicit non-goals

The package is not intended to add Codex coding-agent behavior such as filesystem agency, shell execution, background coding jobs, or its own multi-agent framework. Those are different products from an `ellmer` provider and are not implied by Chat compatibility.

It is also not intended to circumvent payment, subscription, access, or rate-limit rules. The product description is “an ellmer provider for using Codex access associated with an eligible ChatGPT subscription,” not “a way to avoid paying for the API.”

## Decision rules for future work

1. Preserve the defining product identity: direct ChatGPT-subscription access through a normal `ellmer` Chat.
2. Do not introduce a runtime dependency on the Codex CLI or another local service.
3. Prefer `ellmer`'s public semantics over package-specific substitutes.
4. Treat explicitly requested model-facing Chat capabilities as required; treat only parallel/batch helpers as the accepted stable-release exception.
5. Prefer a clearly reported upstream limitation over fabricated or silently degraded behavior.
6. Validate fixes at both layers: deterministic offline regression coverage and opt-in real subscription use when the change concerns live behavior.
7. Keep security, secret redaction, independent-project disclosure, and protocol uncertainty visible rather than hidden for marketing or release convenience.

## Task-history basis

This baseline was reconstructed from the project's Codex tasks on 2026-08-20 and 2026-08-21, especially:

- `Build pure-R Codex proof of concept`
- `Review ellmercodex progress`
- `Continue ellmercodex implementation`
- `Add models and effort selection`
- `Check Ellmer tool support`
- `Add ellmer tool-calling support`
- `Support ellmer Chat surfaces`
- `Review current implementation issues`
- `Implement full ellmer Chat support`
- `Review ellmer Chat support`
- `Document package for CRAN`
- `Create package feature test script`
- `Troubleshoot codex_models`
- `Select reasoning effort`
- `Remove runtime Codex CLI dependency`

The earliest full prompts established the subscription-based, pure-R, no-CLI companion-package identity. Later tasks expanded the initial v0.1 milestone into the current compatibility contract, made tool calling and other model-facing Chat capabilities mandatory, accepted the narrow parallel/batch exception for stable status, and reasserted real end-to-end validation plus the absence of any runtime Codex CLI dependency.

# Manual live compatibility check

This directory contains an opt-in maintainer check for the experimental live
transport. It is not sourced during package loading, examples, tests, builds,
or `R CMD check`.

Run it only when you intend to let `ellmercodex` inspect its package-scoped
credential, open a browser if authentication is missing, and send two short
prompts to the selected Codex model:

```sh
ELLMERCODEX_RUN_LIVE_TESTS=true \
ELLMERCODEX_MODEL=gpt-5.6-luna \
R --vanilla -f inst/manual-tests/live.R
```

The script prints only the package's redacted account summary and ordinary
model output. It never reads another application's credentials. It deliberately
does not log out afterward, because doing so would delete the package's saved
session.

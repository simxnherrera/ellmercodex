# Maintainer verification checks

`test-all.R` is the complete verification runner. By default it runs the
fixture-backed test suite without network access and writes logs, JUnit/CSV
summaries, session information, and serialized turn artifacts to a timestamped
directory. Set `ELLMERCODEX_TEST_OUTPUT` to keep those artifacts outside the
repository.

Run the offline suite:

```sh
ELLMERCODEX_TEST_OUTPUT=/tmp/ellmercodex-test-results \
Rscript --vanilla inst/manual-tests/test-all.R
```

Set `ELLMERCODEX_RUN_LIVE_TESTS=true` to add real Codex checks. If the
account-specific model catalog is empty, the live acceptance fails because
non-empty discovery is part of the release contract. To exercise the explicit
browser login path even when a package credential already exists, also set
`ELLMERCODEX_LIVE_EXPLICIT_LOGIN=true`:


```sh
ELLMERCODEX_RUN_LIVE_TESTS=true \
ELLMERCODEX_LIVE_EXPLICIT_LOGIN=true \
ELLMERCODEX_TEST_OUTPUT=/tmp/ellmercodex-live-test \
Rscript --vanilla inst/manual-tests/test-all.R
```

Live checks inspect only the package-scoped credential, use redacted account
artifacts, and do not log out afterward. The runner tests both account-catalog
default selection and an explicit model. Set `ELLMERCODEX_MODEL` to choose the
explicit model. If it is absent from `codex_models()`, also set
`ELLMERCODEX_LIVE_EFFORT` to an effort accepted by the service, for example
`medium` for `gpt-6-luna`. `live.R` remains the smaller two-prompt smoke check
and accepts the same variables. To check every GPT-6 model ID with `medium`
effort, run the dedicated family smoke test:

```sh
ELLMERCODEX_RUN_LIVE_TESTS=true \
Rscript --vanilla inst/manual-tests/live-model-family.R
```

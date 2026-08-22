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
account-specific model catalog is empty, provide an explicitly selected model
with `ELLMERCODEX_MODEL`:


```sh
ELLMERCODEX_RUN_LIVE_TESTS=true \
ELLMERCODEX_MODEL=gpt-5.6-luna \
ELLMERCODEX_TEST_OUTPUT=/tmp/ellmercodex-live-test \
Rscript --vanilla inst/manual-tests/test-all.R
```

Live checks inspect only the package-scoped credential, use redacted account
artifacts, and do not log out afterward. `live.R` remains as the smaller
two-prompt compatibility smoke check.

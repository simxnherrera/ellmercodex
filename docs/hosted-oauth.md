# Persist ChatGPT credentials on a single-process Linux VM

This guide follows OpenAI's guidance for self-hosted VMs
(<https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms>).
It covers **your own** R application on **your own** VM, signed in with your
own ChatGPT account. OpenAI limits ChatGPT plan usage to open-source and
locally hosted apps: an app that serves other people, or a paid or remotely
hosted service, needs OpenAI's approval through the
[interest form](https://openai.com/form/sign-in-with-chatgpt-interest/)
before it can use this flow.

The supported setup is one R application process on one Linux VM, running as
a dedicated operating-system user (`ellmercodex`) under systemd. The VM has a
durable filesystem mounted at `/var/lib/ellmercodex`; it stays attached when
the service restarts or the application code is redeployed. A VM or container
replacement must reattach the volume before the application starts.

ellmercodex serializes refreshes across R processes with a lock directory, but
this guide still assumes one app process: several replicas sharing one
registration are outside its scope.

## Prepare the host

Create the service account and credential directory as the VM administrator.
Keep it outside the application release directory, the home directory, and
any ephemeral container layer:

```sh
sudo useradd --system --home-dir /var/lib/ellmercodex --shell /usr/sbin/nologin ellmercodex
sudo install -d -o ellmercodex -g ellmercodex -m 0700 /var/lib/ellmercodex/credentials
```

Set the credential directory in the systemd unit, before R starts:

```ini
[Service]
User=ellmercodex
Group=ellmercodex
Environment=ELLMERCODEX_HOME=/var/lib/ellmercodex/credentials
ExecStart=/usr/bin/Rscript /srv/ellmercodex/app.R
```

The app should call `chat_codex()` when needed. It must not call
`codex_login()` during startup: a missing credential is handled by an
operator, not by a browser launch in unattended service code.

## Create the VM's host ID

Each host needs its own stable `ext_agent_host_id`. Create the VM's ID once,
before importing any credential, as the service user:

```sh
sudo -u ellmercodex env ELLMERCODEX_HOME=/var/lib/ellmercodex/credentials \
  Rscript -e 'invisible(ellmercodex:::codex_host_id())'
```

This writes `/var/lib/ellmercodex/credentials/host-id`. Never copy a laptop's
`host-id` file to the VM.

## Sign in on your computer, then transfer the credential

A `127.0.0.1` callback reaches the computer running the browser, not the VM.
So sign in on your own computer, in a separate credential directory used only
for this transfer:

```r
Sys.setenv(ELLMERCODEX_HOME = "~/ellmercodex-vm-transfer")
library(ellmercodex)
auth <- codex_login(persist = TRUE)
codex_account()
```

Then stop the app and copy **only** `credentials.json` to the VM over SSH,
keeping the VM's own `host-id`:

```sh
scp ~/ellmercodex-vm-transfer/credentials.json vm.example.org:/tmp/credentials.json
ssh vm.example.org 'sudo install -o ellmercodex -g ellmercodex -m 0600 \
  /tmp/credentials.json /var/lib/ellmercodex/credentials/credentials.json && rm /tmp/credentials.json'
rm -r ~/ellmercodex-vm-transfer
```

Delete the local transfer copy without calling `codex_logout()`: logout would
revoke the refresh token that the VM now uses. From now on the VM owns the
refreshes, and its next sign-in uses its own host ID.

Start the app. A fresh R process loads the credential without opening a
browser. Access tokens last one hour; the package refreshes them and writes
each rotated refresh token back to `credentials.json`. Refresh tokens stay
valid for 30 days after each refresh, so an app idle for more than 30 days
needs a new transfer.

As an alternative to the transfer, you can sign in directly on the VM through
an SSH tunnel (`ssh -L 1455:127.0.0.1:1455 vm.example.org`), with
`options(browser = function(url) cat(url, "\n"))` in the VM's R session.
Keep that URL private: on reauthorization it carries an ID token hint.

## Operate the credential

- `credentials.json` holds the issued client ID, the ID token, and the access
  and refresh tokens in plain JSON with mode `0600`. It is not encrypted. Any
  code running as the service user can use it. Protect the volume and its
  backups, and never commit or serve them.
- Avoid printing the result of `codex_login()` or logging tokens, request
  headers, authorization URLs, or the credential file.
- To sign out, stop the app and run `codex_logout()` as the service user with
  the same `ELLMERCODEX_HOME`. It revokes the refresh token, deletes
  `credentials.json`, and keeps `host-id`. You can also disconnect the app in
  ChatGPT settings; OpenAI does not notify the app, and the next refresh then
  fails with `codex_refresh_error`.
- If a refresh token is rejected (for example `invalid_grant` or
  `refresh_token_reused`), the package removes the tokens but keeps the
  registration. Transfer a fresh credential or sign in again.
- OpenAI notes that host-specific usage attribution and revocation of
  transferred sessions are not yet available.

The package's automated tests use temporary credential directories and
simulated OAuth responses. A live restart check on your VM is optional and
operator-run: transfer the credential, restart the service, and verify a
redacted `codex_account()` status from the new process.

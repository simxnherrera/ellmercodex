# Persist OAuth credentials on a single-process Linux VM

The supported hosted setup is one R application process on one Linux VM,
running as a dedicated operating-system user (`ellmercodex`) under systemd.
The VM has a durable filesystem mounted at `/var/lib/ellmercodex`; it remains
attached when the service restarts or the application code is redeployed.
The application and the one-time login run as the same OS user and use the
same httr2 version and `HTTR2_OAUTH_CACHE` value. A VM/container replacement
must reattach the volume before the application starts. This contract does not
cover several R workers, replicas, or simultaneous processes refreshing one
credential: httr2 does not provide a cross-process refresh lock for this cache.

## Prepare the host

Create the service account and cache directory as the VM administrator. Keep
the volume outside the application release directory, home directory, and any
ephemeral container layer. Grant only this service account and administrators
access to it:

```sh
sudo useradd --system --home-dir /var/lib/ellmercodex --shell /usr/sbin/nologin ellmercodex
sudo install -d -o ellmercodex -g ellmercodex -m 0700 /var/lib/ellmercodex/oauth-cache
```

Set the environment variable in the systemd unit for the app, before R starts:

```ini
[Service]
User=ellmercodex
Group=ellmercodex
Environment=HTTR2_OAUTH_CACHE=/var/lib/ellmercodex/oauth-cache
ExecStart=/usr/bin/Rscript /srv/ellmercodex/app.R
```

The app must remain a **single R process**. Configure the service manager to
start one instance; do not run a separate scheduler, worker, or second replica
with this cache. The app should call `chat_codex()` when needed. It must not
call `codex_login()` during startup: a missing credential should be handled by
an operator, not by a browser launch in unattended service code.

## Sign in once

Stop the app, then run an interactive R session on the VM as `ellmercodex`,
with the cache variable set to exactly the service value. The OAuth callback
listens on the VM loopback port 1455. From the operator's laptop, forward that
port over SSH (`ssh -L 1455:127.0.0.1:1455 vm.example.org`) and open the
authorization URL printed by the R session in the laptop browser. Keep the SSH
session open until the callback completes. Run
`auth <- codex_login(persist = TRUE)`
in the VM's R session; inspect only `codex_account()` for a redacted status.
The login R process and the app must never run together against this cache.

```sh
sudo -u ellmercodex env HTTR2_OAUTH_CACHE=/var/lib/ellmercodex/oauth-cache R --vanilla
```

```r
library(ellmercodex)
options(browser = function(url) cat(url, "\n"))
auth <- codex_login(persist = TRUE)
codex_account()
```

Keep that authorization URL private and out of service logs. The callback is
local to the VM and reaches the waiting R process through the SSH tunnel.

Exit R and start the app. A fresh R process loads the cached credential
without opening a browser. Restarting the service or deploying new app code
retains access as long as the volume, path, OS user, and client cache remain
the same. On expiration, httr2 refreshes the token and writes a rotated
refresh token back to that cache. Avoid printing the result of `codex_login()`
or logging tokens, request headers, cache contents, or OAuth responses.

## Operate the credential

- The cache root is `/var/lib/ellmercodex/oauth-cache`; httr2 writes the
  package's encrypted token file below its `ellmercodex` subdirectory. The
  encryption is obfuscation controlled by httr2, **not** a platform secret
  manager or OS keychain. R code with access to the cache can use the token.
  Protect the mounted volume and backups accordingly; do not commit or expose
  them through the app or a web server.
- Back up the volume only to an access-controlled encrypted backup, or elect
  to replace it by signing in again. Restore it with the same service-account
  access and cache path before starting the app. A missing, unreadable, or
  invalidated cache requires the explicit login procedure above.
- To sign out, stop the app and run `codex_logout()` in an R process under the
  same user and cache variable. Then exit R. This removes the package's local
  cache entry; it does not revoke a remote session. Run `codex_login()` again
  before restarting the app if it should continue to authenticate.
- `persist = FALSE` keeps credentials only in that R process. They disappear
  at process exit and are unsuitable for restart persistence.
- httr2 1.3.0 prunes cached token files older than 30 days when the package
  loads. A long-idle app may need an operator login again. This release also
  changed the cache location and filename hash: upgrading from an older httr2
  can cause a one-time cache miss and require re-authentication. Keep the
  supported httr2 version available in both the login and app R sessions.

The package's automated tests use temporary caches and simulated OAuth
responses. A live restart or volume-reattachment check on your VM is optional
and operator-run: sign in, restart the service, and verify a redacted
`codex_account()` status from the new process. Never put that check in CRAN
tests or unattended deployment hooks.

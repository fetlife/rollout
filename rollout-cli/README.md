# rollout-cli

A separately installable, read-only HTTP client for Rollout. Requires Ruby 3.1+;
installation does not pull in Rollout, Rails, database drivers, or Redis.

```sh
gem install rollout-cli
rollout --help
```

For this unreleased checkout, build and install from `rollout-cli/`:

```sh
gem build rollout-cli.gemspec
gem install --local rollout-cli-0.1.0.gem
```

**Integration status:** this repository implements the client and specifies API v1.
The existing rollout-ui 0.9.2 routes do not implement this contract. A companion
rollout-ui release and host authentication/mount changes are required before use.
No production deployment or end-to-end FetLife integration has been verified.
See [HTTP contract](HTTP_API.md) and the repository's
[integration checklist](../docs/rollout-cli-integration.md).

## Configure a profile

Create `~/.config/rollout/config.json` (or use `--config PATH`):

```json
{
  "profiles": {
    "production": {
      "url": "https://app.example.com/internal/rollout/v1",
      "environment": "production",
      "token_env": "ROLLOUT_PRODUCTION_TOKEN"
    },
    "staging": {
      "url": "https://staging.example.com/internal/rollout/v1",
      "environment": "staging",
      "token_file": "staging.token"
    }
  }
}
```

The URL points to the API v1 root, not the browser UI. `environment` must exactly
match the server's configured environment; a mismatch fails before printing data.
Every data command requires `--profile`; there is no implicit/default environment.
Use distinct profiles/URLs when exposing multiple Rollout instances.

Inject the named token environment variable with your secret manager, or put the
bearer token in the designated file. Do not place tokens in shell command arguments,
URLs, or the config JSON. There is deliberately no `--token` option. Relative token
file paths resolve from the config directory. Token files must be owned by the
current user with no group/other permissions (typically `chmod 600`). Config files
must also be owned by the current user and not group/other writable. Keep their
parent directory private (`chmod 700 ~/.config/rollout`). Do not commit credentials.

HTTPS verifies server certificates and hostnames using Ruby's trust store. No
insecure TLS option is provided. For local development only, an HTTP URL with host
`localhost`, `127.0.0.1`, or `[::1]` requires `"allow_http": true` in that profile.
Redirects are rejected, proxy environment variables are ignored, and cookies are
never sent. The client does not print headers, response error bodies, URLs, or
exception details that could contain credentials. There are no automatic retries.

## Commands and output

```sh
rollout features --profile production --json
rollout show FEATURE --profile production --json
rollout history FEATURE --since 2026-09-01 --profile production --json
rollout history --since 24h --profile production --json
```

- `features` returns stored flag state sorted by name. Default output summarizes
  percentage, groups, and explicit user count; JSON includes full state.
- `show` includes percentage, groups, explicit users, and data. This is stored
  targeting configuration, not an evaluation for a particular user or runtime
  group predicate. A nonexistent flag returns exit 4 rather than synthetic state.
- `history FEATURE` reads that feature's retained changes. Omitting FEATURE reads
  the separately retained global stream. Events include before/after data, context,
  and timestamps, newest first. Default output shows all returned change details.

`--limit N` applies to features/history (default 100, range 1–1000). Results are one
bounded request, with no automatic pagination. `meta.truncated` means more matching
*retained* records exist beyond the response limit; increase the limit if needed.
A false value never proves historical completeness. V1 cannot enumerate beyond
1000 matching records; pagination is follow-up work.

History's optional `--since` is inclusive. It accepts a UTC calendar date
(`2026-09-01`), RFC3339 timestamp with timezone, or positive integer duration with
`s`, `m`, `h`, or `d` suffix. Relative durations use the client clock once per command;
`24h` means exactly 86,400 seconds. The client sends UTC with six fractional digits.
Omitting `--since` requests the newest retained events without a time lower bound.
An empty result means no retained matches, not proof that nothing changed.

`--json` writes one API v1 JSON object and a newline to stdout, preserving the
contract's fields (including metadata and additive server fields). No progress or
diagnostics are mixed into it. Errors write a concise diagnostic to stderr and
leave stdout empty. Default output is for humans; scripts should use JSON. `--help`
and `--version` are plain text, do not connect, and need no configuration.

| Exit | Meaning |
| --- | --- |
| 0 | Success, including empty results and results marked truncated |
| 2 | Invalid command/options, profile, config, or credentials |
| 3 | HTTP 401/403: authentication or authorization denied |
| 4 | HTTP 404: feature or API route not found |
| 5 | Other HTTP error (including redirects/429), invalid schema/JSON, environment mismatch, or oversized response |
| 6 | Connection, TLS, or timeout failure |

Requests have a 5-second connection timeout, 10-second read/write timeouts, and a
30-second overall deadline. Responses are capped at 1 MiB before JSON parsing;
features with very large user/data fields may exceed this even at limit 1. The CLI
fails explicitly instead of silently cutting off state. Servers should cap output
as well. Broken output pipes terminate successfully for shell pipelines.

## History limitations

Current retention is count-based, not time-based. The per-feature and global
streams are independently bounded. A busy feature may lose old records quickly;
the global stream may lose them faster. `max_events` reports the configured count
cap, not a promise about the duration covered or the count currently stored.

The metadata always reports `completeness: "unknown"`. Even a requested time later
than the oldest retained event does not prove completeness: logging could have
been disabled, records deleted, or writes made outside Rollout. Feature deletion
clears that feature's history and emits no deletion event. Previously retained
global updates may remain until their independent retention removes them. A
recreated feature therefore need not have its earlier per-feature history.

Disabled/unavailable logging returns an empty event list with `enabled: false`.
Global history is unavailable when global logging is disabled. Clients must use
this field rather than interpret the empty list as evidence of no activity.

## Development

```sh
cd rollout-cli
bundle install
bundle exec rake test
```

From the root, `bundle exec rake spec:cli` invokes that package's bundle. The CLI
has its own CI job and does not change core/adapters' dependency requirements.
Tests exercise the actual executable, local HTTP sockets, rejection of untrusted
TLS, credential permissions, bounds, and the v1 response contract. These are
client/transport tests with controlled responses, not host/server integration tests.

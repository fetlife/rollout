# rollout-cli integration work

## What this checkout provides

`rollout-cli/` is an independent gem with the `rollout` executable, a versioned
HTTP client, and local transport/contract tests. It has no core/adapters dependency.
The root gem excludes its files. [CLI usage](../rollout-cli/README.md) and the
[normative API v1 contract](../rollout-cli/HTTP_API.md) describe the supported surface.
No rollout-ui or fetlife-web source was modified as part of this client change.
The local test server returns controlled contract responses; it does not run
rollout-ui, Rails authorization, or a production adapter.

## Verified source context (2026-09-30 local checkouts)

- Core `lib/rollout/logging.rb` exposes `events(feature, limit:)` and
  `global_events(limit:)`; events have feature, name, data, context, and created_at.
- `rollout-active_record-adapter/lib/rollout/adapters/active_record.rb` independently
  prunes feature/global visibility, selects newest records by timestamp/id, and
  returns those records in chronological order. API output reverses that order.
- Core `Rollout#delete` clears per-feature logging; it does not emit a deletion event.
- Sibling rollout-ui's `lib/rollout/ui/web.rb` supports browser index/show JSON;
  `helpers.rb#feature_to_hash` excludes explicit users and history. These routes
  are not API v1 and should retain their existing behavior.
- Sibling fetlife-web `Gemfile.lock` pins rollout 3.1.0, rollout-ui 0.9.2, and
  rollout-active_record-adapter 0.1.0. `config/initializers/redis.rb` creates both
  `$rollout` and `$rollout_randomized` with the same Active Record adapter and
  `logging: { history_length: 100, global: true }`.
- FetLife `config/routes.rb` configures the UI with `$rollout` and the resolved
  employee nickname as actor, mounting it at `/admin/rollout`. Outside development,
  the browser mount uses `Constraints::Trusted`. This is not evidence of bearer
  token authorization or a usable CLI API.

Deployment/runtime and installed production gem versions were not checked.

## Companion rollout-ui change

1. Add an opt-in read-only API Rack/Sinatra application and four GET routes from
   the contract. Keep browser routing and existing JSON responses compatible.
   Configure the instance and server environment explicitly; document that the
   host must authenticate and authorize the mount. Do not ship an open default mount.
2. Add v1 serializers including explicit user targeting and retained event details.
   Check actual existence before `get`, since unknown flags can synthesize state.
   Validate query parameters, percent-decoding, maximum count, time format, and
   response bytes. Read N+1 retained events to determine truncation; do not scan
   or merge per-feature histories to construct global history.
3. Include disabled/global-disabled history metadata and accurate count-based
   retention limitations. Do not claim completeness or deletion coverage. The
   oldest retained timestamp may be null when no bounded query supplies it.
4. Test using actual Rollout plus the Active Record adapter: independent retention,
   equal-time ordering, inclusive filters, N+1 truncation, zero retained events,
   disabled logging, deletion/recreation, and retained global updates after feature
   deletion. Verify state reads do not create features/events. Test mount prefixes,
   encoded feature names, JSON failures, byte limits, and non-GET rejection.
5. Release a new rollout-ui version implementing API v1; document its Rollout and
   adapter compatibility. Existing 0.9.2 browser JSON must not be advertised as
   supporting this CLI.

## Companion fetlife-web change

1. Upgrade/pin rollout-ui to that release. Choose a separate API URL, for example
   `/internal/rollout/v1`, and set its environment from deployment configuration.
   Use `$rollout` to match the browser's stored state. The shared adapter means
   changes from the randomized instance share the same feature/global histories;
   this API does not evaluate randomized decisions.
2. Wrap only the new API mount in host-owned bearer authentication and authorization.
   Choose the host's token issuance/storage/rotation/revocation mechanism after
   reviewing existing authentication patterns. Give human/service principals a
   narrowly scoped rollout-read capability; explicitly authorize exposure of
   user IDs, feature data, and employee context. Do not reuse browser cookies or
   merely assume the existing browser route constraint authorizes bearer tokens.
3. Return JSON 401/403, never login redirects; keep mutation routes inaccessible
   through the API mount. Filter Authorization in Rails, proxy, and APM logs.
   Preserve browser authorization and actor attribution for existing writes.
4. Issue separate environment-specific credentials through the host's supported
   mechanism; distribute via a secret manager/private files and document revocation.
   Configure TLS and the reverse proxy to preserve encoded feature segments, enforce
   request/rate/response bounds, and avoid caching authenticated responses.
5. Add host request tests covering absent, invalid, expired/revoked, insufficiently
   privileged, and valid credentials, plus read-only method restrictions. Confirm
   no cookie is necessary and environment mismatches are caught by the client.

## End-to-end acceptance still required

Run the packaged executable against the actual authenticated application in a
controlled staging environment, with the real rollout-ui API and Active Record
adapter. Exercise list, show, feature history, global history, date/duration filters,
limit truncation, missing flags, and auth failures. Compare results with known
state and mutations made through the authorized application; confirm the CLI itself
creates no database changes or logging events. Verify shared-instance visibility,
retention/deletion behavior, proxy encoding, TLS, response limits, and secret
redaction. Record deployed gem versions and test evidence before claiming production
integration is complete. A production smoke check requires a deployed endpoint
and approved read credential; neither was established by this change.

Longer retention, deletion events, durable audit guarantees, richer pagination,
write commands, and MCP remain follow-up work.

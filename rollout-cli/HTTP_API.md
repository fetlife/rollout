# Rollout HTTP API v1 contract

Status: contract implemented by rollout-cli 0.1.0; companion rollout-ui endpoints
and host integration remain to be implemented. Existing browser JSON routes are
not compatible. This document is the normative contract for the companion work.

## Transport and host responsibilities

Mount an opt-in read-only API in rollout-ui, separately from its browser routes,
at a host-chosen base URL such as `/internal/rollout/v1`. All paths below are relative
to this base. The server configures a fixed `environment` string and a Rollout
instance; never derive environment from a client query/header. Every request uses:

```http
Authorization: Bearer <host-issued token>
Accept: application/json
```

The host authenticates tokens and authorizes read access to the chosen instance,
state, explicit users, and event context. rollout-ui must not implement a token
store or reuse employee browser cookies. Mount only behind the host's authentication
and authorization boundary. No routes should be publicly accessible by default.
The API mount must not expose browser mutation routes or CSRF exemptions for them.
Return JSON 401/403, not redirects to login. Allow GET only (405 otherwise).

Use HTTPS, `Content-Type: application/json`, `Cache-Control: no-store`, no response
compression for this client (`Accept-Encoding: identity`), and no credential or
Authorization logging. Configure reverse proxies/APM to redact credentials too.
Cap query values and response size server-side. Never silently omit targeting
fields, context, or changes to fit a byte bound: return an error instead. The
client rejects responses over 1 MiB, redirects, and non-200 success codes.

Successful bodies are objects with integer `api_version: 1` and string
`environment`. JSON examples below are illustrative, not observations of production.
Required fields must be present, including fields whose value is null. Additive
fields are allowed; changing meanings/types/removing fields requires a new version.
Timestamps are RFC3339 with explicit timezone, preferably UTC with microseconds.
Percentages are JSON numbers in [0, 100]. Names, group names, and user identifiers
are strings. `data` and `context` are JSON objects. Preserve before/after nulls and
value types. Do not serialize events using implementation-specific Ruby objects.

## Routes

| Method/path | Query | Behavior |
| --- | --- | --- |
| `GET /features` | `limit` | Stored features sorted by name (ascending UTF-8 byte order), first N |
| `GET /features/{feature}` | none | Full stored state, 404 if not present |
| `GET /features/{feature}/history` | `limit`, `since` | Newest retained feature events, 404 if feature not present |
| `GET /history` | `limit`, `since` | Newest retained events in the independent global stream |

A feature name is a single percent-encoded UTF-8 path segment, 1–256 bytes after
decoding, with no control characters. Decode once; test spaces, percent, slash,
Unicode, and dot segments through the deployed proxy/router. The client percent
encodes slash and dots rather than letting names alter the request path. If a host
cannot route a stored name losslessly, return an explicit error; never target a
different flag. Do not use `rollout.get` alone to determine existence: it can
synthesize inactive state. Check `rollout.adapter.feature_exists?` first.

`limit` is a decimal integer in [1, 1000], default 100. Reject invalid/duplicate or
unknown query parameters with 400. `since` is an inclusive RFC3339 lower bound;
the client translates dates/durations before requesting. Omitted means no lower
bound. Echo the normalized UTC six-fractional-digit `since` (or null) in history
metadata. A future lower bound is valid and normally returns no records.

## Feature state

```json
{
  "api_version": 1,
  "environment": "production",
  "feature": {
    "name": "chat",
    "percentage": 25.5,
    "groups": ["staff"],
    "users": ["123"],
    "data": {"description": "Chat"}
  }
}
```

Use string arrays for groups/users, sorted in byte order for deterministic output.
State describes stored targeting, not whether a specific user would be active.
Registered group predicates and randomization settings are not evaluated here.
Existing rollout-ui `feature_to_hash` omits `users`; add a dedicated v1 serializer
rather than accidentally changing the browser contract.

The list response uses the same feature object shape:

```json
{
  "api_version": 1,
  "environment": "production",
  "features": [
    {"name": "chat", "percentage": 25.5, "groups": ["staff"], "users": ["123"], "data": {"description": "Chat"}}
  ],
  "meta": {"limit": 100, "truncated": false}
}
```

`truncated` is true only if more stored features exist beyond this limit. There is
no cursor or offset in v1. This is a bounded view, not an exhaustive export when
more than 1000 flags exist. Reads need not form a transactional snapshot across
features. A feature disappearing during serialization should be omitted or yield
a documented retriable error, never synthetic empty state.

## History

```json
{
  "api_version": 1,
  "environment": "production",
  "events": [
    {
      "feature": "chat",
      "name": "update",
      "data": {"before": {"percentage": 0}, "after": {"percentage": 25.5}},
      "context": {"actor": "employee-nickname"},
      "created_at": "2026-09-30T11:00:00.000000Z"
    }
  ],
  "meta": {
    "limit": 100,
    "truncated": false,
    "scope": "feature",
    "feature": "chat",
    "since": "2026-09-01T00:00:00.000000Z",
    "retention": {
      "enabled": true,
      "max_events": 100,
      "oldest_available_at": null,
      "completeness": "unknown",
      "deletion_events": false
    }
  }
}
```

For global history, `scope` is `"global"` and `feature` is null. Each event still
has its feature name. Return events newest first, including those exactly equal
to `since`. Preserve adapter ordering as the tie-breaker for equal timestamps;
with the Active Record adapter this is descending event id. Do not invent event
IDs/cursors from timestamps: equal timestamps are possible.

`meta.truncated` describes only additional matching retained events beyond the
response limit. It is independent of retention loss. It may be false when the
requested period substantially predates all retained history.

`retention` fields:

- `enabled`: whether logging is available and enabled for this scope. For global
  scope also require `logging.global`. Disabled means `events: []`,
  `truncated: false`, and `oldest_available_at: null`.
- `max_events`: current configured `logging.history_length`, or null if unavailable.
  This is a count cap applied on writes, not a duration guarantee; changing it
  does not necessarily immediately prune previously stored data.
- `oldest_available_at`: actual oldest retained timestamp in the entire requested
  scope **before** `since` and response limiting, or null if empty or not known.
  Never substitute the oldest timestamp in a partial response. It is acceptable
  to return null in the initial implementation to keep reads bounded.
- `completeness`: always `"unknown"` in v1. Existing storage cannot prove a complete
  audit trail, even when results are empty or not truncated.
- `deletion_events`: false. Deletion clears per-feature history and emits no
  deletion event. Older global update records may remain independently.

Global/per-feature histories are independently capped. Do not derive global
history by merging feature histories: deletion and independent pruning make that
incorrect. Logging enabled now is not proof that it was always enabled.

### Bounded implementation using current Rollout

Check feature existence for scoped requests. If logging is unavailable, or global
logging is disabled for a global request, return the disabled envelope. Otherwise:

1. Read `logging.events(feature, limit: limit + 1)` or
   `logging.global_events(limit: limit + 1)`.
2. Current adapters return the newest N records in oldest-to-newest order. Reverse
   this result; preserve its equal-timestamp ordering. Filter by `created_at >= since`
   if present, then calculate `truncated = matches.length > limit` and take `limit`.
   Reading newest N+1 is sufficient for an inclusive lower-bound-only filter:
   older unseen events cannot match if the inspected older boundary does not match.
3. Serialize the event readers (`feature`, `name`, `data`, `context`, `created_at`),
   explicitly converting timestamps to UTC ISO8601 with microseconds.
4. Set retention from the configured logger. Leave `oldest_available_at` null unless
   a separate bounded adapter query can determine it accurately.

This does not require changing adapter retention or adding pagination. The list
route can sort `rollout.features` and only load state for N+1 names. The current
name-list API itself materializes all names; response bounding is not a guarantee
of O(limit) backend work. Read bounds do not protect against a single very large
feature/event, so enforce the serialized byte limit too.

## Errors

Use JSON error bodies such as:

```json
{"api_version":1,"environment":"production","error":{"code":"feature_not_found","message":"Feature not found"}}
```

| HTTP | Meaning |
| --- | --- |
| 400 | Invalid name, parameter, duplicate parameter, or unsupported query |
| 401 | Missing/invalid/expired token (include appropriate Bearer challenge) |
| 403 | Authenticated principal lacks rollout read access |
| 404 | Unknown feature/route |
| 405 | Unsupported method |
| 413 | Serialized response would exceed server output bound |
| 429 | Host rate limit |
| 500/503 | Server/storage failure or unavailable service |

Authentication middleware may return its own JSON error shape. The client maps
HTTP status to exit code, never prints server error text, and does not retry.
An unsupported history backend should yield 503 rather than fabricated empty
history; only known disabled logging yields the disabled success envelope.

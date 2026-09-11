# Upgrading to Rollout 3

Rollout 3 keeps feature evaluation in the `rollout` gem and moves Redis
persistence to `rollout-redis`. Existing Redis keys stay in place. This is
not the later Active Record / PostgreSQL migration.

## 1. Update dependencies

Add the adapter gem next to `rollout`:

```ruby
gem "rollout"
gem "rollout-redis"
```

Use matching Rollout 3 releases of both gems. If you use
[rollout-ui](https://github.com/fetlife/rollout-ui), wait for a Rollout
3-compatible UI release before upgrading production.

## 2. Update requires and initialization

```ruby
# Before
require "redis"
require "rollout"

$redis = Redis.new
$rollout = Rollout.new(
  $redis,
  randomize_percentage: true,
  logging: { history_length: 100, global: true },
)
```

```ruby
# After
require "redis"
require "rollout"
require "rollout/redis"

$redis = Redis.new
$rollout = Rollout.new(
  backend: Rollout::Redis::Backend.new($redis),
  randomize_percentage: true,
  logging: { history_length: 100, global: true },
)
```

Pass the same Redis client, database, and namespace you already use. Repeat
this change at every initialization site, including jobs, scripts, and
consoles.

`redis-namespace` still works:

```ruby
$ns = Redis::Namespace.new(Rails.env, redis: $redis)
$rollout = Rollout.new(backend: Rollout::Redis::Backend.new($ns))
```

## 3. Breaking changes

| Area | Breaking change | Required action |
| --- | --- | --- |
| Storage configuration | `Rollout.new(redis, options)` now requires `backend:`. | Wrap the existing client in `Rollout::Redis::Backend.new(redis)` and pass options as keywords. |
| Storage access | `rollout.storage` is removed. `rollout.backend` returns an adapter, not the Redis client. | Keep your own Redis client reference if application code needs direct access. |
| Logging storage | `logging: { storage: other_redis }` is no longer supported. The Redis backend stores features and history through the same client. | Applications using separate history storage cannot preserve that setup with the current adapter. Removing the option does not migrate existing history. |
| Custom logging | `Logger#log` and `Logger#update` are removed. Built-in logging is no longer an observer. | Use Rollout mutations and `logging.with_context` rather than calling those methods directly. |
| Feature construction | `Feature.new(name, rollout:, state: payload)` no longer accepts a name argument or raw Redis payload. | Prefer `rollout.get(name)`. Direct construction requires `Feature.new(state: feature_state, rollout: rollout, options: rollout.options)`. |
| Feature serialization | `feature.serialize` is removed. | Use `feature.to_feature_state` for a backend-neutral snapshot. Redis encoding belongs to `Rollout::Redis::Codec`. |
| History decoding | `Logging::Event.from_raw` is removed. | Decode persisted Redis members with `Rollout::Redis::Codec.decode_event(value, score)`. |

## 4. History and lifecycle

History reads can request a bound. `limit` is the newest N events, returned
oldest-to-newest. Omit `limit` to read the full retained history. `0` returns
no events.

```ruby
rollout.logging.events(:chat, limit: 10)
rollout.logging.global_events(limit: 10)
rollout.logging.last_event(:chat)
```

`last_event` reads one persisted member. It does not load the complete
history.

| Operation | Feature state | Per-feature history | Global history |
| --- | --- | --- | --- |
| `delete`, logging enabled | Removed | Removed | Retained |
| `delete`, logging disabled | Removed | Retained | Retained |
| `logging.delete` | Unchanged | Removed | Retained |
| `clear!` | Removed | Retained | Retained |

`clear!` still resets each feature first, so logging-enabled instances record
a reset event before the state is deleted. History remains subject to
`history_length`. The Redis registry key is removed after clearing, including
when it was already empty.

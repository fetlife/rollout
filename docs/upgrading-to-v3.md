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

## 3. Keep existing Redis data and cohorts

Do not export, import, or flush Redis for this upgrade. Feature payloads,
the feature registry, and history keys are reused.

Keep evaluation options unchanged:

- `randomize_percentage`
- `id_user_by`
- `use_sets`
- group definitions (`define_group` is still in-process and must be
  registered on boot)

Do not change hashing as part of this upgrade. CRC32 assignment is
unchanged.

## 4. Breaking changes

These are the application changes that fail if left as Rollout 2:

| Rollout 2 | Rollout 3 |
| --- | --- |
| `gem "rollout"` pulls in `redis` | Add `gem "rollout-redis"` |
| `require "rollout"` is enough for Redis | Also `require "rollout/redis"` |
| `Rollout.new(redis, options)` | `Rollout.new(backend: Rollout::Redis::Backend.new(redis), **options)` |
| `rollout.storage` | `rollout.backend` |
| `logging: { storage: other_redis }` | Removed. History is stored by the backend |
| `Feature.new(name, rollout:, state: payload)` | `Feature.new(state:, rollout:, options:)`. `state` is a `FeatureState` |
| `feature.serialize` | Removed. Persistence encoding lives in `Rollout::Redis::Codec` |

Logging no longer registers itself as an `Observable` observer. Public
history methods stay: `logging.events`, `logging.global_events`,
`logging.with_context`, `logging.without`. `Logger#update` and `Logger#log`
are gone.

Custom observers still receive `:update` with before/after `Feature`
objects.

`Feature#name` remains a symbol. Persistence snapshots use strings via
`FeatureState`.

The first write after upgrade may serialize a cleared percentage as `0.0`
instead of `0`. Rollout 2 and 3 both read that payload. Unread keys are
left as they are.

## 5. Verify before production

On staging, against a copy of production Redis or a restored backup:

1. Confirm existing features still appear in `rollout.features`.
2. Check representative users for features at 0%, partial percentage, 100%,
   user allowlists, and groups.
3. Activate, deactivate, edit metadata, and delete a disposable feature.
4. If logging is enabled, confirm a mutation writes history and that
   `delete` removes that feature's history.
5. If you use rollout-ui, edit a feature, confirm the stale-form token still
   works, and check history.

## 6. Deploy and roll back

1. Back up Redis.
2. Deploy the dependency and initialization changes together.
3. Restart every process that constructs a `Rollout` instance.

Avoid mixed Rollout 2 and Rollout 3 writers.

To roll back, restore the Rollout 2 gems and the previous initialization.
Existing Redis data still loads. Pause writers first if you need a clean
cutover.

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

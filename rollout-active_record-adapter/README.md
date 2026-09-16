# rollout-active_record-adapter

Active Record adapter for [rollout](https://github.com/FetLife/rollout).

The adapter stores feature state and history in two application tables. It
depends on Active Record, not Rails or a database driver. Applications supply
the driver for PostgreSQL, MySQL, SQLite, or another Active Record database.

## Install

```ruby
gem "rollout", "~> 3.1"
gem "rollout-active_record-adapter"
```

Requires Ruby 2.7+ and Active Record 7.1 through 8.x.

## Setup

### Rails

```bash
bin/rails generate rollout:active_record:install
bin/rails db:migrate
```

Multi-database applications can target a specific database:

```bash
bin/rails generate rollout:active_record:install --database=web
```

The generator copies a migration into the host application. It does not run
migrations. Bundler loads the gem; no extra `require` is needed.

### Standalone Active Record

```ruby
require "rollout-active_record-adapter"

Rollout::ActiveRecord::Schema.create(ActiveRecord::Base.connection)
```

## Initialize

### Rails

```ruby
adapter = Rollout::Adapters::ActiveRecord.new(
  base_record_class: ApplicationRecord,
)

$rollout = Rollout.new(
  adapter: adapter,
  logging: {
    history_length: 100,
    global: true,
  },
)
```

### Standalone

```ruby
require "rollout-active_record-adapter"

adapter = Rollout::Adapters::ActiveRecord.new
$rollout = Rollout.new(adapter: adapter)
```

Standalone applications can omit `base_record_class`; the adapter defaults to
`ActiveRecord::Base`. Table names default to `rollout_features` and
`rollout_events` and can be overridden:

```ruby
Rollout::Adapters::ActiveRecord.new(
  base_record_class: ApplicationRecord,
  features_table_name: "rollout_features",
  events_table_name: "rollout_events",
)
```

Pass an abstract record class that owns the intended connection. The adapter
defines its own models and does not use application models for features or
events.

Caching is disabled by default (`cache_ttl_seconds: nil`). Pass
`cache_ttl_seconds:` to keep an in-process cache of feature state, including
missing features:

```ruby
Rollout::Adapters::ActiveRecord.new(
  base_record_class: ApplicationRecord,
  cache_ttl_seconds: 10,
)
```

The cache belongs to the adapter instance and can serve many requests for as
long as that instance lives. Separate processes and adapter instances do not
share it. Cached entries refresh on the next read after `cache_ttl_seconds`;
reads do not extend expiry. Mutations always use the database. Committed writes
through the same adapter instance invalidate affected entries. Other processes
and adapter instances see those writes after the cache TTL expires. Cache reads
are skipped inside an open database transaction.

Users, groups, metadata, and event payloads are stored as JSON-encoded text.

## Writes

Feature mutations persist state and history in one Active Record transaction.
If the mutation block raises, neither the feature nor its history is saved.
`ActiveRecord::Rollback` is re-raised so observers do not run.

When a mutation runs inside an open application transaction, it uses a
savepoint (`requires_new: true`). A failed mutation rolls back independently.
A successful mutation still commits only if the outer transaction commits.
Observers run when the adapter returns, which may be before the outer
transaction commits.

Existing feature rows are locked for update. Feature names are case-sensitive,
including on MySQL.

`delete_feature` removes feature state and leaves history in place.
`clear_features` deletes remaining feature rows and leaves history in place.

## Migrate from Redis

This is a one-off copy into empty `rollout_features` and `rollout_events`
tables. Feature state is copied by default. Pass `include_history: true` to
copy retained Redis history as well. Pause feature-configuration writes for
the cutover.

Keep both adapter gems in the bundle until the cutover is complete. Loading
the Active Record adapter does not load the Redis adapter.

```ruby
require "rollout/adapters/redis"

redis = Rollout::Adapters::Redis.new($redis)
active_record = Rollout::Adapters::ActiveRecord.new(
  base_record_class: ApplicationRecord,
)

migration = Rollout::ActiveRecord::Migration.new(
  source: redis,
  destination: active_record,
  include_history: true,
)

result = migration.dry_run
abort result.summary unless result.success?

result = migration.run
abort result.summary unless result.success?
```

`dry_run` is a preflight check: it validates the Redis export and that the
destination tables are empty. It does not insert rows or run verification.
If `run` fails verification, `result.summary` includes the first mismatch
and `result.differences` lists all of them.

Use the same Redis client, database, and namespace the application already
uses.

1. Create the Active Record tables.
2. Freeze feature writes (UI, jobs, consoles, scripts).
3. Dry run, then run. Both Rollout tables must be empty.
4. Point every process at the Active Record adapter.
5. Smoke-test feature evaluation, then resume writes.

Keep group definitions and evaluation options such as
`randomize_percentage` and `id_user_by`. Redis remains available for
rollback until writes resume.

`export_features` reports registered keys that are missing and feature
keys that are not in the registry. Clean those up before migrating. An
occupied destination is left unchanged.

## Testing this gem

```bash
bundle exec rspec
```

The suite defaults to SQLite. PostgreSQL and MySQL use the same examples:

```bash
ROLLOUT_AR_ADAPTER=postgresql bundle exec rspec
ROLLOUT_AR_ADAPTER=mysql2 bundle exec rspec
```

Optional connection settings:

- PostgreSQL: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- MySQL: `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`
- Redis migration examples: `REDIS_HOST`, `REDIS_PORT`, `REDIS_MIGRATION_DB`.
  Locally those examples skip when Redis is not running. CI requires Redis.

From the repository root:

```bash
bundle exec rake spec:active_record
```

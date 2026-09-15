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
migrations.

### Standalone Active Record

Create the tables with the same schema the generator installs:

```ruby
require "rollout/adapters/active_record"

Rollout::ActiveRecord::Schema.create(ActiveRecord::Base.connection)
```

## Initialize

```ruby
require "rollout"
require "rollout/adapters/active_record"

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

Existing feature rows are locked for update. Concurrent first writes of the
same feature can raise a uniqueness error. Concurrent writes can also
temporarily exceed the configured global history length until a later
mutation with global logging enabled prunes the excess. The adapter does
not retry conflicts.

Feature names are case-sensitive, including on MySQL.

`delete_feature` removes feature state and leaves history in place.
`clear_features` deletes remaining feature rows and leaves history in place.

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

From the repository root:

```bash
bundle exec rake spec:active_record
```

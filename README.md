# rollout

Fast feature flags.

Upgrading from Rollout 2? Follow the [Rollout 3 upgrade guide](docs/upgrading-to-v3.md)
before updating your dependencies.

[![Gem Version](https://badge.fury.io/rb/rollout.svg)](https://badge.fury.io/rb/rollout)
[![CI](https://github.com/fetlife/rollout/actions/workflows/test.yml/badge.svg)](https://github.com/fetlife/rollout/actions/workflows/test.yml)
[![Code Climate](https://codeclimate.com/github/FetLife/rollout/badges/gpa.svg)](https://codeclimate.com/github/FetLife/rollout)
[![Test Coverage](https://codeclimate.com/github/FetLife/rollout/badges/coverage.svg)](https://codeclimate.com/github/FetLife/rollout/coverage)

## Install it

```bash
gem install rollout -v '~> 3.1'
gem install rollout-redis-adapter -v '~> 0.1'
```

```ruby
gem "rollout", "~> 3.1"
gem "rollout-redis-adapter", "~> 0.1"
```

## How it works

Initialize a rollout object. I assign it to a global var.

```ruby
require "redis"
require "rollout"
require "rollout/adapters/redis"

$redis = Redis.new
$rollout = Rollout.new(adapter: Rollout::Adapters::Redis.new($redis))
```


Update data specific to a feature:

```ruby
$rollout.set_feature_data(:chat, description: 'foo', release_date: 'bar', whatever: 'baz')
```

Check whether a feature is active for a particular user:

```ruby
$rollout.active?(:chat, User.first) # => true/false
```

Check whether a feature is active globally:

```ruby
$rollout.active?(:chat)
```

You can activate features using a number of different mechanisms.

## Groups

Rollout ships with one group by default: "all", which does exactly what it
sounds like.

You can activate the all group for the chat feature like this:

```ruby
$rollout.activate_group(:chat, :all)
```

You might also want to define your own groups. We have one for our caretakers:

```ruby
$rollout.define_group(:caretakers) do |user|
  user.caretaker?
end
```

You can activate multiple groups per feature.

Deactivate groups like this:

```ruby
$rollout.deactivate_group(:chat, :all)
```

Groups need to be defined every time your app starts. The logic is not persisted
anywhere.

## Specific Users

You might want to let a specific user into a beta test or something. If that
user isn't part of an existing group, you can let them in specifically:

```ruby
$rollout.activate_user(:chat, @user)
```

Deactivate them like this:

```ruby
$rollout.deactivate_user(:chat, @user)
```

## User Percentages

If you're rolling out a new feature, you might want to test the waters by
slowly enabling it for a percentage of your users.

```ruby
$rollout.activate_percentage(:chat, 20)
```

The algorithm for determining which users get let in is this:

```ruby
Zlib.crc32(user.id.to_s) < (2**32 - 1) / 100.0 * percentage
```

The result is deterministic: the same user is always in or out at a given
percentage, and users already included remain included as the percentage
increases.

Deactivate all percentages like this:

```ruby
$rollout.deactivate_percentage(:chat)
```

_Note that activating a feature for 100% of users will also make it active
"globally". That is when calling Rollout#active? without a user object._

In some cases you might want to have a feature activated for a random set of
users. It can come specially handy when using Rollout for split tests.

```ruby
$rollout = Rollout.new(
  adapter: Rollout::Adapters::Redis.new($redis),
  randomize_percentage: true,
)
```

When on `randomize_percentage` will make sure that 50% of users for feature A
are selected independently from users for feature B.

## Global actions

While groups can come in handy, the actual global setter for a feature does not require a group to be passed.

```ruby
$rollout.activate(:chat)
```

In that case you can check the global availability of a feature using the following

```ruby
$rollout.active?(:chat)
```

And if something is wrong you can set a feature off for everybody using

Deactivate everybody at once:

```ruby
$rollout.deactivate(:chat)
```

For many of our features, we keep track of error rates using redis, and
deactivate them automatically when a threshold is reached to prevent service
failures from cascading. See https://github.com/jamesgolick/degrade for the
failure detection code.

## Check Rollout Feature

You can inspect the state of your feature using:

```ruby
feature = $rollout.get(:chat)
feature.to_hash
# => { percentage: 5.0, groups: [:caretakers], users: ["1"], data: {} }
```

## Namespacing

Rollout separates its keys from other keys in the data store using the
"feature" keyspace.

If you're using redis, you can namespace keys further to support multiple
environments by using the
[redis-namespace](https://github.com/resque/redis-namespace) gem.

```ruby
gem "redis-namespace"
```

```ruby
require "redis"
require "redis/namespace"
require "rollout"
require "rollout/adapters/redis"

$ns = Redis::Namespace.new(Rails.env, redis: $redis)
$rollout = Rollout.new(adapter: Rollout::Adapters::Redis.new($ns))
$rollout.activate_group(:chat, :all)
```

This example stores the chat feature at `development:feature:chat` when
`Rails.env` is `"development"`.

## Frontend / UI

* [rollout-ui](https://github.com/fetlife/rollout-ui)
* [Rollout-Dashboard](https://github.com/fiverr/rollout_dashboard/)

These integrations may not yet support Rollout 3. Use a version compatible with
the Rollout release you install. If you depend on rollout-ui, wait for a
Rollout 3-compatible UI release before upgrading production.

## Implementations in other languages

*   Python: https://github.com/asenchi/proclaim
*   PHP: https://github.com/opensoft/rollout
*   Clojure: https://github.com/yeller/shoutout
*   Perl: https://metacpan.org/pod/Toggle
*   Golang: https://github.com/SalesLoft/gorollout


## Contributors

*   James Golick - Creator - https://github.com/jamesgolick
*   Eric Rafaloff - Maintainer - https://github.com/EricR


## Testing

Install dependencies first. Core and the Redis adapter have separate Gemfiles:

```bash
bundle install
bundle install --gemfile=rollout-redis-adapter/Gemfile
```

Core tests do not need Redis:

```bash
bundle exec rake spec
```

Redis adapter tests flush database 7 by default. Use a disposable instance,
not a shared or production Redis. Start Redis in a separate terminal:

```bash
docker run --rm -p 6379:6379 redis:7-alpine
```

Then run:

```bash
bundle exec rake spec:redis
```

Optional connection settings: `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB`. `REDIS_DB`
overrides the default database 7 that is flushed before each example.

## Releasing

Each gem has its own version and tag.

- Configure a RubyGems trusted publisher for the gem you are releasing. Use
  repository owner `fetlife`, repository `rollout`, workflow filename
  `release.yml`, and no GitHub environment.
- Update and commit the version in `lib/rollout/version.rb` or
  `rollout-redis-adapter/rollout-redis-adapter.gemspec`.
- Tag the release commit with `rollout/vX.Y.Z` or
  `rollout-redis-adapter/vX.Y.Z`, matching the gem version.
- Push the tag with `git push origin <tag>`. CI publishes the selected gem and
  creates its GitHub release.

Use package-prefixed tags, not `vX.Y.Z`. Publish core first when the adapter
depends on a new core version.

## Copyright

Copyright (c) 2010-InfinityAndBeyond BitLove, Inc. See LICENSE for details.

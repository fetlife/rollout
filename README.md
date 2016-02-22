# rollout

Feature flippers.

[![Build Status](https://travis-ci.org/FetLife/rollout.svg?branch=master)](https://travis-ci.org/FetLife/rollout)
[![Code Climate](https://codeclimate.com/github/FetLife/rollout/badges/gpa.svg)](https://codeclimate.com/github/FetLife/rollout)
[![Dependency
Status](https://gemnasium.com/FetLife/rollout.svg)](https://gemnasium.com/FetLife/rollout)
[//]: # ([![Test Coverage](https://codeclimate.com/github/FetLife/rollout/badges/coverage.svg)](https://codeclimate.com/github/FetLife/rollout/coverage))

## MAKE SURE TO READ THIS: 2.X Changes and Migration Path

As of rollout-2.x, only one key is used per feature for performance reasons.
The data format is `percentage|user_id,user_id,...|group,_group...`. This has
the effect of making concurrent feature modifications unsafe, but in practice,
I doubt this will actually be a problem.

This also has the effect of rollout no longer being dependent on redis. Just
give it something that responds to `set(key,value)`, `get(key)` and
`del(key)`.

If you have been using the 1.x format, you can initialize Rollout with
`migrate: true` and it'll do its best to automatically migrate your old
features to the new format. There will be some performance impact, but it
should be limited and short-lived since each feature only needs to get
migrated once.

## Rollout::Legacy

If you'd prefer to continue to use the old layout in redis, `Rollout::Legacy`
is a copy and paste of the old code :-).

## Install it

```bash
gem install rollout
```

## How it works

Initialize a rollout object. I assign it to a global var.

```ruby
require 'redis'

$redis   = Redis.new
$rollout = Rollout.new($redis)
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
CRC32(user.id) % 100 < percentage
```

So, for 20%, users 0, 1, 10, 11, 20, 21, etc would be allowed in. Those users
would remain in as the percentage increases.

Deactivate all percentages like this:

```ruby
$rollout.deactivate_percentage(:chat)
```

_Note that activating a feature for 100% of users will also make it active
"globally". That is when calling Rollout#active? without a user object._

In some cases you might want to have a feature activated for a random set of
users. It can come specially handy when using Rollout for split tests.

```ruby
$rollout = Rollout.new($redis, randomize_percentage: true)
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
failures from cascading. See http://github.com/jamesgolick/degrade for the
failure detection code.

## Namespacing

Rollout separates its keys from other keys in the data store using the
"feature" keyspace.

If you're using redis, you can namespace keys further to support multiple
environments by using the
[redis-namespace](https://github.com/resque/redis-namespace) gem.

```ruby
$ns = Redis::Namespace.new(Rails.env, redis: $redis)
$rollout = Rollout.new($ns)
$rollout.activate_group(:chat, :all)
```

This example would use the "development:feature:chat:groups" key.

## Implementations in other languages

*   Python: http://github.com/asenchi/proclaim
*   PHP: https://github.com/opensoft/rollout
*   Clojure: https://github.com/tcrayford/shoutout


## Contributors

*   James Golick - Creator - https://github.com/jamesgolick
*   Eric Rafaloff - Maintainer - https://github.com/EricR


## Copyright

Copyright (c) 2010-InfinityAndBeyond BitLove, Inc. See LICENSE for details.

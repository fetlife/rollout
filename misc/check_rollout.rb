#!/usr/bin/env ruby

require "rubygems"
require "yajl"
require "open-uri"

output = Yajl::Parser.parse(open(ARGV[0]))
percentage = output["percentage"].to_i

puts Yajl::Encoder.encode(output)

if percentage == 100
  exit(0)
else
  exit(2)
end

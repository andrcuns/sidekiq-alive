# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in sidekiq_alive.gemspec
gemspec

gem "sidekiq", ENV["SIDEKIQ_VERSION_RANGE"] ||= "~> 8"

group :test do
  # rackup is not compatible with sidekiq < 7 due to rack version requirement
  if ["7", "8"].any? { |range| ENV["SIDEKIQ_VERSION_RANGE"]&.include?(range) }
    gem "rackup", "~> 2.2.0"
  else
    gem "rack", "< 3"
    gem "webrick", "< 2"
  end
end

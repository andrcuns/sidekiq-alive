# rubocop:disable Naming/FileName

# frozen_string_literal: true

require "sidekiq"
require "sidekiq/api"
require "singleton"
require "sidekiq_alive/version"
require "sidekiq_alive/config"

module SidekiqAlive
  class << self
    def start
      Sidekiq.configure_server do |sq_config|
        sq_config.on(:startup) do
          SidekiqAlive::Worker.sidekiq_options(queue: current_queue)
          sq_config.queues.unshift(current_queue)

          logger.info(startup_info)

          register_current_instance
          store_alive_key
          SidekiqAlive::Worker.perform_async(hostname)
          @server_pid = fork { SidekiqAlive::Server.run! }

          logger.info(successful_startup_text)
        end

        sq_config.on(:quiet) do
          unregister_current_instance
          config.shutdown_callback.call
        end

        sq_config.on(:shutdown) do
          Process.kill("TERM", @server_pid) unless @server_pid.nil?
          Process.wait(@server_pid) unless @server_pid.nil?

          unregister_current_instance
          config.shutdown_callback.call
        end
      end
    end

    def current_queue
      "#{config.queue_prefix}-#{hostname}"
    end

    def register_current_instance
      register_instance(current_instance_register_key)
    end

    def unregister_current_instance
      # Delete any pending jobs for this instance
      logger.info(shutdown_info)
      purge_pending_jobs
      redis.call("DEL", current_instance_register_key)
    end

    def registered_instances
      redis.scan("MATCH", "#{config.registered_instance_key}::*").map { |key| key }
    end

    def purge_pending_jobs
      jobs = Sidekiq::ScheduledSet.new.scan('"class":"SidekiqAlive::Worker"')
      logger.info("[SidekiqAlive] Purging #{jobs.count} pending for #{hostname}")
      jobs.each(&:delete)

      logger.info("[SidekiqAlive] Removing queue #{current_queue}")
      Sidekiq::Queue.new(current_queue).clear
    end

    def current_instance_register_key
      "#{config.registered_instance_key}::#{hostname}"
    end

    def store_alive_key
      redis.call("SET", current_lifeness_key, Time.now.to_i, ex: config.time_to_live.to_i)
    end

    def redis
      Sidekiq.redis { |r| r }
    end

    def alive?
      redis.ttl(current_lifeness_key) != -2
    end

    # CONFIG ---------------------------------------

    def setup
      yield(config)
    end

    def logger
      config.logger || Sidekiq.logger
    end

    def config
      @config ||= SidekiqAlive::Config.instance
    end

    def current_lifeness_key
      "#{config.liveness_key}::#{hostname}"
    end

    def hostname
      ENV["HOSTNAME"] || "HOSTNAME_NOT_SET"
    end

    def shutdown_info
      "Shutting down sidekiq-alive!"
    end

    def startup_info
      info = {
        hostname: hostname,
        port: config.port,
        ttl: config.time_to_live,
        queue: current_queue,
        liveness_key: current_lifeness_key,
        register_key: current_instance_register_key,
      }

      "Starting sidekiq-alive: #{info}"
    end

    def successful_startup_text
      "Successfully started sidekiq-alive, registered instances: #{registered_instances.join("\n\s\s- ")}"
    end

    def register_instance(instance_name)
      redis.call("SET", instance_name, Time.now.to_i, ex: config.registration_ttl.to_i)
    end
  end
end

require "sidekiq_alive/worker"
require "sidekiq_alive/server"

SidekiqAlive.start unless ENV.fetch("DISABLE_SIDEKIQ_ALIVE", "").casecmp("true").zero?

# rubocop:enable Naming/FileName

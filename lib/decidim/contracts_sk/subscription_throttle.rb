# frozen_string_literal: true

require "digest"

module Decidim
  module ContractsSk
    # In-process rate limit of e-mail alert subscription requests
    # (civora-org/civora-platform#121): per e-mail address and per client IP,
    # each a fixed count in a sliding window.
    #
    # Privacy: neither the address nor the IP is kept. Counters are keyed by
    # a SHA-256 of "<kind>:<value>" and live in process memory only; they
    # vanish on restart and are pruned once their window passed. The IP never
    # reaches the database or the log.
    #
    # Limits of the design, stated honestly: the counters are per process, so
    # a host running N workers allows up to N times the limit overall. A host
    # that wants a global limit adds Rack::Attack in front (POST
    # <mount>/subscriptions); this class is the floor that works without any
    # host configuration, not a replacement for it.
    class SubscriptionThrottle
      WINDOW = 1.hour
      LIMITS = { email: 3, ip: 10 }.freeze
      # Bound on remembered keys: past it the stale ones are dropped, and if
      # that is not enough the table is cleared (a flood of distinct keys must
      # not grow memory without limit; a cleared table only loosens the limit).
      MAX_KEYS = 50_000

      def self.default
        @default ||= new
      end

      def initialize(limits: LIMITS, window: WINDOW)
        @limits = limits
        @window = window
        @hits = Hash.new { |hash, key| hash[key] = [] }
        @mutex = Mutex.new
      end

      # Records one attempt and answers whether it may go ahead. EVERY kind is
      # counted before the answer, so a refused attempt still counts toward
      # the other limits (a flood from one IP stays refused).
      def allow?(email:, ip:, now: Time.current)
        @mutex.synchronize do
          prune(now)
          counts = { email: hit(:email, email, now), ip: hit(:ip, ip, now) }
          counts.all? { |kind, count| count <= @limits.fetch(kind) }
        end
      end

      def reset!
        @mutex.synchronize { @hits.clear }
      end

      def size
        @mutex.synchronize { @hits.size }
      end

      private

      def hit(kind, value, now)
        stamps = @hits[Digest::SHA256.hexdigest("#{kind}:#{value}")]
        stamps.reject! { |stamp| stamp <= now - @window }
        stamps << now
        stamps.size
      end

      def prune(now)
        return if @hits.size < MAX_KEYS

        @hits.delete_if { |_key, stamps| stamps.last <= now - @window }
        @hits.clear if @hits.size >= MAX_KEYS
      end
    end
  end
end

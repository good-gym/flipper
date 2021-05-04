require 'delegate'

module Flipper
  module Adapters
    # Internal: Adapter that wraps another adapter with the ability to memoize
    # adapter calls in memory. Used by flipper dsl and the memoizer middleware
    # to make it possible to memoize adapter calls for the duration of a request.
    class Memoizable < SimpleDelegator
      include ::Flipper::Adapter

      FeaturesKey = :flipper_features
      GetAllKey = :all_memoized

      # Internal
      attr_reader :cache

      # Public: The name of the adapter.
      attr_reader :name

      # Internal: The adapter this adapter is wrapping.
      attr_reader :adapter

      # Private
      def self.key_for(key)
        "feature/#{key}"
      end

      # Public
      def initialize(adapter, cache = nil)
        super(adapter)
        @adapter = adapter
        @name = :memoizable
        @cache = cache || {}
      end

      # Public
      def features
        cache.fetch(FeaturesKey) { cache[FeaturesKey] = @adapter.features }
      end

      # Public
      def add(feature)
        result = @adapter.add(feature)
        expire_features_set
        result
      end

      # Public
      def remove(feature)
        result = @adapter.remove(feature)
        expire_features_set
        expire_feature(feature)
        result
      end

      # Public
      def clear(feature)
        result = @adapter.clear(feature)
        expire_feature(feature)
        result
      end

      # Public
      def get(feature)
        cache.fetch(key_for(feature.key)) { cache[key_for(feature.key)] = @adapter.get(feature) }
      end

      # Public
      def get_multi(features)
        uncached_features = features.reject { |feature| cache[key_for(feature.key)] }

        if uncached_features.any?
          response = @adapter.get_multi(uncached_features)
          response.each do |key, hash|
            cache[key_for(key)] = hash
          end
        end

        result = {}
        features.each do |feature|
          result[feature.key] = cache[key_for(feature.key)]
        end
        result
      end

      def get_all
        response = nil
        if cache[GetAllKey]
          response = {}
          cache[FeaturesKey].each do |key|
            response[key] = cache[key_for(key)]
          end
        else
          response = @adapter.get_all
          response.each do |key, value|
            cache[key_for(key)] = value
          end
          cache[FeaturesKey] = response.keys.to_set
          cache[GetAllKey] = true
        end

        # Ensures that looking up other features that do not exist doesn't
        # result in N+1 adapter calls.
        response.default_proc = ->(memo, key) { memo[key] = default_config }
        response
      end

      # Public
      def enable(feature, gate, thing)
        result = @adapter.enable(feature, gate, thing)
        expire_feature(feature)
        result
      end

      # Public
      def disable(feature, gate, thing)
        result = @adapter.disable(feature, gate, thing)
        expire_feature(feature)
        result
      end

      private

      def key_for(key)
        self.class.key_for(key)
      end

      def expire_feature(feature)
        cache.delete(key_for(feature.key))
      end

      def expire_features_set
        cache.delete(FeaturesKey)
      end
    end
  end
end

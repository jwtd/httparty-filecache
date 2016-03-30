module HTTParty
  module HTTPCache
    class NoResponseError < StandardError; end

    mattr_accessor  :perform_caching,
                    :apis,
                    :logger,
                    :cache,
                    :timeout_length,
                    :cache_stale_backup_time,
                    :exception_callback

    self.perform_caching = false
    self.apis = {}
    self.timeout_length = 5 # 5 seconds
    self.cache_stale_backup_time = 300 # 5 minutes

    def self.included(base)
      base.class_eval do
        alias_method_chain :perform, :caching
      end
    end

    def perform_with_caching
      if cacheable?
        if response_in_cache?
          log_message("Retrieving response from cache")
          response_from_cache
        else
          validate
          begin
            httparty_response = timeout(timeout_length) do
              perform_without_caching
            end
            httparty_response.parsed_response
            if httparty_response.response.is_a?(Net::HTTPSuccess)
              log_message("Storing good response in cache")
              store_in_cache(httparty_response)
              httparty_response
            else
              retrieve_and_store_backup(httparty_response)
            end
          rescue *exceptions => e
            if exception_callback && exception_callback.respond_to?(:call)
              exception_callback.call(e, cache_key_name, normalized_uri)
            end
            retrieve_and_store_backup
          end
        end
      else
        log_message("Caching off")
        perform_without_caching
      end
    end


    protected


    def cacheable?
      HTTPCache.perform_caching && HTTPCache.apis.keys.include?(uri.host) && http_method == Net::HTTP::Get
    end

    def normalized_uri
      return @normalized_uri if @normalized_uri
      normalized_uri = uri.dup
      normalized_uri.query = sort_query_params(normalized_uri.query)
      normalized_uri.path.chop! if (normalized_uri.path =~ /\/$/)
      normalized_uri.scheme = normalized_uri.scheme.downcase
      @normalized_uri = normalized_uri.normalize.to_s
    end

    def sort_query_params(query)
      query.split('&').sort.join('&') unless query.blank?
    end


    def cache_key_name
      @cache_key_name ||= normalized_uri
    end

    def uri_hash
      @uri_hash ||= Digest::MD5.hexdigest(normalized_uri)
    end

    def response_in_cache?
      cache.exists(cache_key_name)
    end

    def store_in_cache(response, expires = nil)
      cache.set(cache_key_name, response)
      #cache.expire(cache_key_name, (expires || HTTPCache.apis[uri.host][cache_key_name][:expire_in]))
    end

    def response_from_cache
      response = cache.get(cache_key_name)
      puts "response_body_from_cache: #{response.class.name}"
      response
    end


    def backup_key
      "#{cache_key_name}" # Could prefix this "backup"
    end

    def backup_response
      cache.hget(backup_key, uri_hash)
    end

    def backup_exists?
      cache.exists(backup_key) && cache.hexists(backup_key, uri_hash)
    end

    def store_backup(response)
      cache.hset(backup_key, uri_hash, response)
    end

    def retrieve_and_store_backup(httparty_response = nil)
      if backup_exists?
        log_message('using backup')
        response = backup_response
        store_in_cache(response, cache_stale_backup_time)
        response_from(response)
      elsif httparty_response
        httparty_response
      else
        log_message('No backup and bad response')
        raise NoResponseError, 'Bad response from API server or timeout occured and no backup was in the cache'
      end
    end


    def log_message(message)
      logger.info("[HTTPCache]: #{message} for #{normalized_uri} - #{uri_hash.inspect}") if logger
    end

    def timeout(seconds, &block)
      if defined?(SystemTimer)
        SystemTimer.timeout_after(seconds, &block)
      else
        options[:timeout] = seconds
        yield
      end
    end

    def exceptions
      if (RUBY_VERSION.split('.')[1].to_i >= 9) && defined?(Psych::SyntaxError)
        [StandardError, Timeout::Error, Psych::SyntaxError]
      else
        [StandardError, Timeout::Error]
      end
    end

  end
end

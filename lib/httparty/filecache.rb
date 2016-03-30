require 'json'

module HTTParty

  class FileCache

    # Create a new reference to a file cache system.
    # domain:: A string that uniquely identifies this caching
    #          system on the given host
    # root_dir:: The root directory of the cache file hierarchy
    #            The cache will be rooted at root_dir/domain/
    # expiry:: The expiry time for cache entries, in seconds. Use
    #          0 if you want cached values never to expire.

    def initialize(domain = "default", root_dir = "/tmp", expiry = 0)
      @domain  = domain
      @root_dir = root_dir
      @expiry  = expiry
    end

    def exists(key)
      path = get_path(key)
      File.exists?(path)
    end

    # Check to see if a value exists in a hash (to match Redis interface)
    def hexists(hash_name, key)
      exists("#{hash_name}_#{key}")
    end

    # Set a cache value for the given key. If the cache contains an existing value for the key it will be overwritten.
    def set(key, value)
      path = get_path(key)
      File.open(path,'w'){ |f| f.write JSON.pretty_generate(value) }
    end

    # Set a value in a hash (to match Redis interface)
    def hset(hash_name, key, value)
      set("#{hash_name}_#{key}", value)
    end

    # Return the value for the specified key from the cache. Returns nil if the value isn't found.
    def get(key)
      path = get_path(key)

      # expire
      if @expiry > 0 && File.exists?(path) && Time.new - File.new(path).mtime >= @expiry
        FileUtils.rm(path)
      end
      if File.exists?(path)
        return JSON.parse(IO.read(path))
      else
        return nil
      end
    end

    # Get a value in a hash (to match Redis interface)
    def hget(hash_name, key)
      get("#{hash_name}_#{key}")
    end

    # Set the expiration date on the file
    def expire(key, seconds_before_expiration)
      path = get_path(key)
      if seconds_before_expiration > 0 && File.exists?(path) && Time.new - File.new(path).mtime >= seconds_before_expiration
        FileUtils.rm(path)
      else
        # TODO: Figure out how to save expiration timestamp
      end
      @expiry = seconds_before_expiration
    end

    # Delete the value for the given key from the cache
    def delete(key)
      FileUtils.rm(get_path(key))
    end

    # Delete ALL data from the cache, regardless of expiry time
    def clear
      if File.exists?(get_root)
        FileUtils.rm_r(get_root)
        FileUtils.mkdir_p(get_root)
      end
    end

    # Delete all expired data from the cache
    def purge
      @t_purge = Time.new
      purge_dir(get_root) if @expiry > 0
    end

    #-------- private methods ---------------------------------

    private

    def get_path(key)
      @uri = URI(key)
      "#{key_path}/#{key_file}"
    end

    def key_path
      s = @root_dir
      s += "/#{@uri.host}" unless @uri.host.nil?
      unless @uri.path.nil?
        dir  = File.dirname(@uri.path)
        s += dir
      end
      FileUtils.mkdir_p(s) unless File.exists?(s)
      return s
    end

    def key_file
      s = ''
      unless @uri.path.nil?
        base = File.basename(@uri.path)
        s += base
      end
      s += "_#{@uri.query}" unless @uri.query.nil?
      s += "_#{@uri.fragment}" unless @uri.fragment.nil?
      s.gsub(/[\?#=&]/, '_').gsub(/%22/, '').gsub(/(%20|,)/, '-')
    end

    def get_root
      if @root == nil
        @root = File.join(@root_dir, @domain)
      end
      return @root
    end

    def purge_dir(dir)
      Dir.foreach(dir) do |f|
        next if f =~ /^\.\.?$/
        path = File.join(dir, f)
        if File.directory?(path)
          purge_dir(path)
        elsif @t_purge - File.new(path).mtime >= @expiry
          # Ignore files starting with . - we didn't create those
          next if f =~ /^\./
          FileUtils.rm(path)
        end
      end

      # Delete empty directories
      if Dir.entries(dir).delete_if{|e| e =~ /^\.\.?$/}.empty?
        Dir.delete(dir)
      end
    end

  end
end
# require 'memcache'
# require 'memcached'

#typically MemCache/Memcached can be used via the following in rails/init.rb:
#$memcache = MemCache.new(memcache_config[:servers].gsub(' ', '').split(','), memcache_config)
#$memcache = Memcached::Rails.new(memcache_config[:servers].gsub(' ', '').split(','), memcache_config)

#this wrapper lets both work.

####### they have MemCache installed (don't need the wrapper)
if defined? MemCache

Rails.logger.info("cache-money: MemCache installed")
#TODO add logging?
class MemcachedWrapper < ::MemCache
end

########## they have Memcached installed (do need the wrapper)
elsif defined? Memcached
Rails.logger.info("cache-money: Memcached installed")

class Memcached
  alias :get_multi :get #:nodoc:
end

class MemcachedWrapper < ::Memcached
  DEFAULTS = { :servers => '127.0.0.1:11211' }

  attr_reader :logger

  # See Memcached#new for details.
  def initialize(*args)
      opts = DEFAULTS.merge(args.last.is_a?(Hash) ? args.pop : {})

      if opts.respond_to?(:symbolize_keys!)
        opts.symbolize_keys!
      else
        opts = symbolize_keys(opts)
      end
      
      servers = Array(
        args.any? ? args.unshift : opts.delete(:servers)
      ).flatten.compact

      opts[:prefix_key] ||= "#{opts[:namespace]}:"

      @logger = opts[:logger]
      @debug  = opts[:debug]

      super(servers, opts)      
  end

  def symbolize_keys(opts)
    # Destructively convert all keys to symbols.
    if opts.kind_of?(Hash) && !opts.kind_of?(HashWithIndifferentAccess)
      opts.keys.each do |key|
        unless key.is_a?(Symbol)
          opts[key.to_sym] = opts[key]
          opts.delete(key)
        end
      end
    end
    opts
  end
  
  def namespace
    options[:prefix_key]
  end

  # Wraps Memcached::Rails#add to return a text string - for cache money
  def add(key, value, ttl=@default_ttl, raw=false)
    super(key, value, ttl, !raw)
    stored
  rescue Memcached::NotStored
    not_stored
  rescue Memcached::Error
    log_error($!)
    log_error($!) if logger
    not_stored
  end

  def replace(key, value, ttl = @default_ttl, raw = false)
    super(key, value, ttl, !raw)
    stored
  rescue Memcached::NotStored
    not_stored
  rescue Memcached::Error
    log_error($!) if logger
    not_stored
  end
  
  # Wraps Memcached#get so that it doesn't raise. This has the side-effect of preventing you from 
  # storing <tt>nil</tt> values.
  def get(key, raw=false)
    logger.debug("Memcached get: #{key.inspect}") if logger && @debug
    value = super(key, !raw)
    logger.debug("Memcached hit: #{key.inspect}") if logger && @debug
    value
  rescue Memcached::NotFound
    logger.debug("Memcached miss: #{key.inspect}") if logger && @debug
    nil
  rescue TypeError
    log_error($!) if logger
    delete(key)
    logger.debug("Memcached deleted: #{key.inspect}") if logger && @debug
    nil
  rescue Memcached::Error
    log_error($!) if logger
    nil
  end

  def fetch(key, expiry = 0, raw = false)
    value = get(key, !raw)

    if value.nil? && block_given?
      value = yield
      add(key, value, expiry, !raw)
    end

    value
  end

  # Wraps Memcached#cas so that it doesn't raise. Doesn't set anything if no value is present.
  def cas(key, ttl=@default_ttl, raw=false, &block)
    super(key, ttl, !raw, &block)
    stored
  rescue Memcached::NotFound
  rescue TypeError
    log_error($!) if logger
    delete(key)
    logger.debug("Memcached deleted: #{key.inspect}") if logger && @debug
  rescue Memcached::Error
    if $!.is_a?(Memcached::ClientError)
      raise $!
    end
    log_error($!) if logger
  end
  
  def get_multi(*keys)
    keys.flatten!
    super(keys, true)
  rescue TypeError
    log_error($!) if logger
    keys.each { |key| delete(key) }
    logger.debug("Memcached deleted: #{keys.inspect}") if logger && @debug
    {}
  rescue Memcached::Error
    log_error($!) if logger
    {}
  end

  def set(key, value, ttl=@default_ttl, raw=false)
    super(key, value, ttl, !raw)
    stored
  rescue Memcached::Error
    log_error($!) if logger
    not_stored
  end

  def append(key, value)
    super(key, value)
    stored
  rescue Memcached::NotStored
    not_stored
  rescue Memcached::Error
    log_error($!) if logger
  end

  def prepend(key, value)
    super(key, value)
    stored
  rescue Memcached::NotStored
    not_stored
  rescue Memcached::Error
    log_error($!) if logger
  end

  def delete(key)
    super(key)
    deleted
  rescue Memcached::NotFound
    not_found
  rescue Memcached::Error
    log_error($!) if logger
  end
  
  def incr(*args)
    super
  rescue Memcached::NotFound
  rescue Memcached::Error
    log_error($!) if logger
  end

  def decr(*args)
    super
  rescue Memcached::NotFound
  rescue Memcached::Error
    log_error($!) if logger
  end

  alias :reset :quit
  alias :close :quit #nodoc
  alias :flush_all :flush
  alias :compare_and_swap :cas
  alias :"[]" :get
  alias :"[]=" :set    

private

  def stored
    "STORED\r\n"
  end
  
  def deleted
    "DELETED\r\n"
  end
  
  def not_stored
    "NOT_STORED\r\n"
  end
  
  def not_found
    "NOT_FOUND\r\n"
  end

  def log_error(err)
    logger.error("#{err}: \n\t#{err.backtrace.join("\n\t")}") if logger
  end
  
end
else
  Rails.logger.warn 'unable to determine memcache implementation'
end #include the wraper
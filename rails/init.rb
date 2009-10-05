yml = YAML.load(IO.read(File.join(RAILS_ROOT, "config", "memcached.yml")))
memcache_config = yml[RAILS_ENV]
memcache_config.symbolize_keys!

if memcache_config.nil? || memcache_config[:cache_money].nil?
  RAILS_DEFAULT_LOGGER.info 'not loading cache-money'
  class ActiveRecord::Base
    def self.index(*args)
    end
  end
else
  RAILS_DEFAULT_LOGGER.info 'loading cache-money'
  require 'cache_money'

  memcache_config[:logger] = Rails.logger
  $memcache = MemCache.new(memcache_config[:servers], memcache_config)
  # $memcache = Memcached::Rails.new(memcache_config['servers'], memcache_config)

  ActionController::Base.cache_store = :cache_money_mem_cache_store
  ActionController::Base.session_options[:cache] = $memcache if memcache_options[:sessions]
  #silence_warnings {
    Object.const_set "RAILS_CACHE", ActiveSupport::Cache.lookup_store(:cache_money_mem_cache_store)
  #}

  $local = Cash::Local.new($memcache)
  $lock  = Cash::Lock.new($memcache)
  $cache = Cash::Transactional.new($local, $lock)

  class ActiveRecord::Base
    is_cached(:repository => $cache)

    def <=>(other)
      if self.id == other.id then 
        0
      else
        self.id < other.id ? -1 : 1
      end
    end
  end
end

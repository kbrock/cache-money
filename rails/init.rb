yml = YAML.load(IO.read(File.join(RAILS_ROOT, "config", "memcached.yml")))
memcache_config = yml[RAILS_ENV]
memcache_config.symbolize_keys! if memcache_config.respond_to?(:symbolize_keys!)

if defined?(DISABLE_CACHE_MONEY) || ENV['DISABLE_CACHE_MONEY'] == 'true' || memcache_config.nil? || memcache_config[:cache_money] != true
  Rails.logger.info 'cache-money disabled'
  class ActiveRecord::Base
    def self.index(*args)
    end
  end
else
  Rails.logger.info 'cache-money enabled'
  require 'cache_money'

  memcache_config[:logger] = Rails.logger
  $memcache = MemcachedWrapper.new(memcache_config[:servers].gsub(' ', '').split(','), memcache_config)

  #ActionController::Base.cache_store = :cache_money_mem_cache_store
  ActionController::Base.session_options[:cache] = $memcache if memcache_config[:sessions]
  #silence_warnings {
  #  Object.const_set "RAILS_CACHE", ActiveSupport::Cache.lookup_store(:cache_money_mem_cache_store)
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

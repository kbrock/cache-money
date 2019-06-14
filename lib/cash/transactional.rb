module Cash
  class Transactional
    attr_reader :memcache

    def initialize(memcache, lock)
      @memcache, @cache = [memcache, memcache]
      @lock = lock
    end

    def transaction
      exception_was_raised = false
      begin_transaction
      result = yield
    rescue Object => e
      exception_was_raised = true
      raise
    ensure
      begin
        @cache.flush unless exception_was_raised
      ensure
        end_transaction
      end
    end

    def get_multi(*keys)
      # the old memcached wants multiple arguments.
      # the new memcached wants an array of arguments.
      # this will give the new memcached what it wants regardless of what you
      # pass in yourself.
      keys.flatten!
      @cache.get_multi(keys)
    end
    
    def method_missing(method, *args, &block)
      @cache.send(method, *args, &block)
    end

    def respond_to?(method)
      @cache.respond_to?(method)
    end

    private
    def begin_transaction
      @cache = Buffered.push(@cache, @lock)
    end

    def end_transaction
      @cache = @cache.pop
    end
  end
end

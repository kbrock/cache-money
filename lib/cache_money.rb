$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rubygems'
require 'active_support'
require 'active_record'

require 'cash/lock'
require 'cash/transactional'
require 'cash/write_through'
require 'cash/finders'
require 'cash/buffered'
require 'cash/index'
require 'cash/config'
require 'cash/accessor'

require 'cash/request'
require 'cash/fake'
require 'cash/local'

require 'cash/query/abstract'
require 'cash/query/select'
require 'cash/query/primary_key'
require 'cash/query/calculation'

require 'cash/util/array'
require 'cash/util/marshal'

class ActiveRecord::Base
  def self.is_cached(options = {})
    options.assert_valid_keys(:ttl, :repository, :version)
    include Cash unless ancestors.include?(Cash)
    Cash::Config.create(self, options)
  end
end

module Cash
  def self.included(active_record_class)
    active_record_class.class_eval do
      include Config, Accessor, WriteThrough, Finders
      extend ClassMethods
    end
  end

  module ClassMethods
    def self.extended(active_record_class)
      class << active_record_class
        alias_method_chain :transaction, :cache_transaction
      end
    end

    def transaction_with_cache_transaction(*args)
      transaction_without_cache_transaction(*args) do
        repository.transaction { yield }
      end
    end
  end
end

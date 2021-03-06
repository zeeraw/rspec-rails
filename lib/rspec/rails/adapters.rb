require 'delegate'
require 'active_support/concern'
require 'test/unit/assertions'

module RSpec
  module Rails
    class AssertionDelegator < Module
      # @api private
      def initialize(*assertion_modules)
        assertion_class = Class.new(SimpleDelegator) do
          include Test::Unit::Assertions
          assertion_modules.each { |mod| include mod }
        end

        super() do
          # @api private
          define_method :build_assertion_instance do
            assertion_class.new(self)
          end

          # @api private
          def assertion_instance
            @assertion_instance ||= build_assertion_instance
          end

          assertion_modules.each do |mod|
            mod.instance_methods.each do |method|
              class_eval <<-EOM, __FILE__, __LINE__ + 1
                def #{method}(*args, &block)
                  assertion_instance.send(:#{method}, *args, &block)
                end
              EOM
            end
          end
        end
      end
    end

    module SetupAndTeardownAdapter
      extend ActiveSupport::Concern

      module ClassMethods
        # @api private
        #
        # Wraps `setup` calls from within Rails' testing framework in `before`
        # hooks.
        def setup(*methods)
          methods.each do |method|
            if method.to_s =~ /^setup_(fixtures|controller_request_and_response)$/
              prepend_before { send method }
            else
              before         { send method }
            end
          end
        end

        # @api private
        #
        # Wraps `teardown` calls from within Rails' testing framework in
        # `after` hooks.
        def teardown(*methods)
          methods.each { |method| after { send method } }
        end
      end

      # @api private
      def method_name
        @example
      end
    end

    module TestUnitAssertionAdapter
      extend ActiveSupport::Concern

      module ClassMethods
        # @api private
        #
        # Returns the names of assertion methods that we want to expose to
        # examples without exposing non-assertion methods in Test::Unit or
        # Minitest.
        def assertion_method_names
          Test::Unit::Assertions.public_instance_methods.select{|m| m.to_s =~ /^(assert|flunk)/} +
            [:build_message, :message]
        end

        # @api private
        def define_assertion_delegators
          assertion_method_names.each do |m|
            class_eval <<-CODE, __FILE__, __LINE__ + 1
              def #{m}(*args, &block)
                assertion_delegator.send :#{m}, *args, &block
              end
            CODE
          end
        end
      end

      class AssertionDelegator
        include Test::Unit::Assertions
      end

      # @api private
      def assertion_delegator
        @assertion_delegator ||= AssertionDelegator.new
      end

      included do
        define_assertion_delegators
      end
    end
  end
end

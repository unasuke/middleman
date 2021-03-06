require 'middleman-core/sitemap/resource'

module Middleman
  module Sitemap
    module Extensions
      class RequestEndpoints < ConfigExtension
        self.resource_list_manipulator_priority = 0

        # Expose `endpoint`
        expose_to_config :endpoint

        EndpointDescriptor = Struct.new(:path, :request_path, :block) do
          def execute_descriptor(app, resource_list)
            r = EndpointResource.new(
              app.sitemap,
              path,
              request_path
            )
            r.output = block if block

            resource_list.add! r
          end
        end

        # Setup a proxy from a path to a target
        # @param [String] path
        # differs from the output path
        Contract String, Or[{ path: String }, Proc] => EndpointDescriptor
        def endpoint(path, options_hash = ::Middleman::EMPTY_HASH, &block)
          if block_given?
            EndpointDescriptor.new(path, path, block)
          else
            EndpointDescriptor.new(path, options_hash[:path] || path, nil)
          end
        end
      end

      class EndpointResource < ::Middleman::Sitemap::Resource
        Contract Maybe[Proc]
        attr_accessor :output

        def initialize(store, path, request_path)
          super(store, path)
          @request_path = ::Middleman::Util.normalize_path(request_path)
        end

        Contract String
        attr_reader :request_path

        Contract Bool
        def template?
          true
        end

        Contract Args[Any] => String
        def render(*)
          return output.call if output
        end

        Contract Bool
        def ignored?
          false
        end
      end
    end
  end
end

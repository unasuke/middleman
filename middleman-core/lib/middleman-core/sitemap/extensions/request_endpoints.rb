require 'middleman-core/sitemap/resource'

module Middleman
  module Sitemap
    module Extensions
      class RequestEndpoints < ConfigExtension
        self.resource_list_manipulator_priority = 0

        # Expose `endpoint`
        expose_to_config :endpoint

        EndpointDescriptor = Struct.new(:path, :block) do
          def execute_descriptor(app, resources)
            r = ::Middleman::Sitemap::CallbackResource.new(
              app.sitemap,
              path,
              &block
            )

            resources + [r]
          end
        end

        # Setup a proxy from a path to a target
        # @param [String] path
        # differs from the output path
        Contract String, Proc => EndpointDescriptor
        def endpoint(path, &block)
          EndpointDescriptor.new(path, block)
        end
      end
    end
  end
end

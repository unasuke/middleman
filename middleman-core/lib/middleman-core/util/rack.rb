require 'middleman-core/contracts'

module Middleman
  module Util
    include Contracts

    module_function

    Contract String, String, SetOf[String], IsA['::Middleman::Application'], Proc => String
    def rewrite_paths(body, path, exts, app, &_block)
      exts = exts.sort_by(&:length).reverse
      matcher = /([\'\"\(,]\s*|# sourceMappingURL=)([^\s\'\"\)\(>]+(#{::Regexp.union(exts)}))/

      url_fn_prefix = 'url('

      body.dup.gsub(matcher) do |match|
        opening_character = $1
        asset_path = $2

        if asset_path.start_with?(url_fn_prefix)
          opening_character << url_fn_prefix
          asset_path = asset_path[url_fn_prefix.length..-1]
        end

        current_resource = app.sitemap.find_resource_by_destination_path(path)

        begin
          uri = ::Middleman::Util.parse_uri(asset_path)

          if uri.relative? && uri.host.nil? && !(asset_path =~ /^[^\/].*[a-z]+\.[a-z]+\/.*/)
            dest_path = ::Middleman::Util.url_for(app, asset_path, relative: false, current_resource: current_resource)

            resource = app.sitemap.find_resource_by_destination_path(dest_path)

            if resource && (result = yield(asset_path))
              "#{opening_character}#{result}"
            else
              match
            end
          else
            match
          end
        rescue ::Addressable::URI::InvalidURIError
          match
        end
      end
    end
  end
end

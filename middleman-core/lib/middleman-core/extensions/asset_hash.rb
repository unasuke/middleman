require 'middleman-core/util'

class Middleman::Extensions::AssetHash < ::Middleman::Extension
  option :sources, %w(.css .htm .html .js .php .xhtml), 'List of extensions that are searched for hashable assets.'
  option :exts, nil, 'List of extensions that get asset hashes appended to them.'
  option :ignore, [], 'Regexes of filenames to skip adding asset hashes to'
  option :rewrite_ignore, [], 'Regexes of filenames to skip processing for path rewrites'

  def initialize(app, options_hash={}, &block)
    super

    require 'digest/sha1'

    # Allow specifying regexes to ignore, plus always ignore apple touch icons
    @ignore = Array(options.ignore) + [/^apple-touch-icon/]

    # Exclude .ico from the default list because browsers expect it
    # to be named "favicon.ico"
    @exts = options.exts || (app.config[:asset_extensions] - %w(.ico))
  end

  Contract String, Or[String, Pathname], Any => Maybe[String]
  def rewrite_url(asset_path, dirpath, _request_path)
    uri = ::Middleman::Util.parse_uri(asset_path)
    relative_path = !uri.path.start_with?('/')

    full_asset_path = if relative_path
      dirpath.join(asset_path).to_s
    else
      asset_path
    end


    return unless asset_page = app.sitemap.find_resource_by_destination_path(full_asset_path) || app.sitemap.find_resource_by_path(full_asset_path)

    replacement_path = "/#{asset_page.destination_path}"
    replacement_path = Pathname.new(replacement_path).relative_path_from(dirpath).to_s if relative_path
    replacement_path
  end

  # Update the main sitemap resource list
  # @return Array<Middleman::Sitemap::Resource>
  Contract ResourceList => ResourceList
  def manipulate_resource_list(resources)
    resources.each do |r|
      next unless r.destination_path.end_with?('/', *options.sources)
      next if Array(options.rewrite_ignore || []).any? do |i|
        ::Middleman::Util.path_match(i, "/#{r.destination_path}")
      end

      r.filters << ::Middleman::InlineURLRewriter.new(:asset_hash,
                                                      app,
                                                      r,
                                                      url_extensions: @exts,
                                                      ignore: options.ignore,
                                                      proc: method(:rewrite_url))
    end

    # Process resources in order: binary images and fonts, then SVG, then JS/CSS.
    # This is so by the time we get around to the text files (which may reference
    # images and fonts) the static assets' hashes are already calculated.
    resources.sort_by do |a|
      if %w(.svg .svgz).include? a.ext
        0
      elsif %w(.js .css).include? a.ext
        1
      else
        -1
      end
    end.each(&method(:manipulate_single_resource))
  end

  Contract IsA['Middleman::Sitemap::Resource'] => Maybe[IsA['Middleman::Sitemap::Resource']]
  def manipulate_single_resource(resource)
    return unless @exts.include?(resource.ext)
    return if ignored_resource?(resource)
    return if resource.ignored?

    digest = if resource.binary?
      ::Digest::SHA1.file(resource.source_file).hexdigest[0..7]
    else
      # Render without asset hash
      body = resource.render { |f| !f.respond_to?(:filter_name) || f.filter_name != :asset_hash }
      ::Digest::SHA1.hexdigest(body)[0..7]
    end

    resource.destination_path = resource.destination_path.sub(/\.(\w+)$/) { |ext| "-#{digest}#{ext}" }
    resource
  end

  Contract IsA['Middleman::Sitemap::Resource'] => Bool
  def ignored_resource?(resource)
    @ignore.any? do |ignore|
      Middleman::Util.path_match(ignore, resource.destination_path)
    end
  end
end

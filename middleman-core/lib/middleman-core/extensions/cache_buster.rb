# The Cache Buster extension
class Middleman::Extensions::CacheBuster < ::Middleman::Extension
  option :exts, nil, 'List of extensions that get cache busters strings appended to them.', set: true
  option :sources, %w(.css .htm .html .js .php .xhtml), 'List of extensions that are searched for bustable assets.', set: true
  option :ignore, [], 'Regexes of filenames to skip adding query strings to'
  option :rewrite_ignore, [], 'Regexes of filenames to skip processing for path rewrites'

  Contract ResourceList => ResourceList
  def manipulate_resource_list(resources)
    resources.each do |r|
      next unless r.destination_path.end_with?('/', *options.sources)
      next if Array(options.rewrite_ignore || []).any? do |i|
        ::Middleman::Util.path_match(i, "/#{r.destination_path}")
      end

      r.filters << ::Middleman::InlineURLRewriter.new(:cache_buster,
                                                      app,
                                                      r,
                                                      url_extensions: options.exts || app.config[:asset_extensions],
                                                      ignore: options.ignore,
                                                      proc: method(:rewrite_url))
    end
  end

  Contract String, Or[String, Pathname], Any => String
  def rewrite_url(asset_path, _dirpath, _request_path)
    asset_path + '?' + Time.now.strftime('%s')
  end
end

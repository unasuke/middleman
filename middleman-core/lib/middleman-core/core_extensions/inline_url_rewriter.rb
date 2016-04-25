require 'rack'
require 'rack/response'
require 'memoist'
require 'middleman-core/util'
require 'middleman-core/contracts'

module Middleman
  class InlineURLRewriter
    include Contracts

    attr_reader :filter_name
    attr_reader :after_filter

    def initialize(filter_name, app, resource, options={})
      @filter_name = filter_name
      @app = app
      @resource = resource
      @options = options

      @after_filter = @options.fetch(:after_filter, nil)
    end

    Contract String => String
    def execute_filter(body)
      path = "/#{@resource.destination_path}"
      dirpath = ::Pathname.new(File.dirname(path))

      ::Middleman::Util.instrument 'inline_url_rewriter', path: path do
        ::Middleman::Util.rewrite_paths(body, path, @options.fetch(:url_extensions), @app) do |asset_path|
          uri = ::Middleman::Util.parse_uri(asset_path)

          relative_path = uri.host.nil?
          full_asset_path = if relative_path
            dirpath.join(asset_path).to_s
          else
            asset_path
          end

          exts = @options.fetch(:url_extensions)
          next unless exts.include?(::File.extname(asset_path))

          next if @options.fetch(:ignore).any? { |r| ::Middleman::Util.should_ignore?(r, full_asset_path) }

          result = @options.fetch(:proc).call(asset_path, dirpath, path)
          asset_path = result if result

          asset_path
        end
      end
    end
  end

  module CoreExtensions
    class InlineURLRewriter < ::Middleman::Extension
      include Contracts

      expose_to_application rewrite_inline_urls: :add

      REWRITER_DESCRIPTOR = {
        id: Symbol,
        proc: Or[Proc, Method],
        url_extensions: ArrayOf[String],
        source_extensions: ArrayOf[String],
        ignore: ArrayOf[::Middleman::Util::IGNORE_DESCRIPTOR],
        after: Maybe[Symbol]
      }.freeze

      def initialize(app, options_hash={}, &block)
        super

        @rewriters = {}
      end

      Contract REWRITER_DESCRIPTOR => Any
      def add(options)
        @rewriters[options] = options
      end

      def after_configuration
        return if @rewriters.empty?

        rewriters = @rewriters.values.sort do |a, b|
          if b[:after] && b[:after] == a[:id]
            1
          else
            0
          end
        end

        app.use Rack, rewriters: rewriters, middleman_app: @app
      end

      class Rack
        extend Memoist
        include Contracts

        Contract RespondTo[:call], {
          middleman_app: IsA['Middleman::Application'],
          rewriters: ArrayOf[REWRITER_DESCRIPTOR]
        } => Any
        def initialize(app, options={})
          @rack_app = app
          @middleman_app = options.fetch(:middleman_app)
          @rewriters = options.fetch(:rewriters)

          all_source_exts = @rewriters
                            .reduce([]) { |sum, rewriter| sum + rewriter[:source_extensions] }
                            .flatten
                            .uniq
          @source_exts_regex_text = Regexp.union(all_source_exts).to_s

          @all_asset_exts = @rewriters
                            .reduce([]) { |sum, rewriter| sum + rewriter[:url_extensions] }
                            .flatten
                            .uniq
        end

        def call(env)
          status, headers, response = @rack_app.call(env)

          # Allow configuration or upstream request to skip all rewriting
          return [status, headers, response] if env['bypass_inline_url_rewriter'] == 'true'

          path = ::Middleman::Util.full_path(env['PATH_INFO'], @middleman_app)

          return [status, headers, response] unless path =~ /(^\/$)|(#{@source_exts_regex_text}$)/
          return [status, headers, response] unless body = ::Middleman::Util.extract_response_text(response)

          dirpath = ::Pathname.new(File.dirname(path))

          rewritten = ::Middleman::Util.instrument 'inline_url_rewriter', path: path do
            ::Middleman::Util.rewrite_paths(body, path, @all_asset_exts, @middleman_app) do |asset_path|
              uri = ::Middleman::Util.parse_uri(asset_path)

              relative_path = uri.host.nil?

              full_asset_path = if relative_path
                dirpath.join(asset_path).to_s
              else
                asset_path
              end

              @rewriters.each do |rewriter|
                uid = rewriter.fetch(:id)

                # Allow upstream request to skip this specific rewriting
                next if env["bypass_inline_url_rewriter_#{uid}"] == 'true'

                exts = rewriter.fetch(:url_extensions)
                next unless exts.include?(::File.extname(asset_path))

                source_exts = rewriter.fetch(:source_extensions)
                next unless source_exts.include?(::File.extname(path))

                ignore = rewriter.fetch(:ignore)
                next if ignore.any? { |r| ::Middleman::Util.should_ignore?(r, full_asset_path) }

                rewrite_ignore = Array(rewriter[:rewrite_ignore] || [])
                next if rewrite_ignore.any? { |i| ::Middleman::Util.path_match(i, path) }

                proc = rewriter.fetch(:proc)

                result = proc.call(asset_path, dirpath, path)
                asset_path = result if result
              end

              asset_path
            end
          end

          ::Rack::Response.new(
            rewritten,
            status,
            headers
          ).finish
        end
      end
    end
  end
end

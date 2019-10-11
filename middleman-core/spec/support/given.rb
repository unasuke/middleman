module Given
  ROOT = File.expand_path('../..', __dir__)
  TMP  = File.join(ROOT, 'tmp')

  class << self
    def fixture(name)
      cleanup!

      if Gem.win_platform?
        # `xcopy "#{File.join(ROOT, 'fixtures', name)}"  "#{TMP}" /e /d /h /r /y`
        p "robocopy #{File.join(ROOT, 'fixtures', name)} #{TMP} /e /r:1"
        `robocopy #{File.join(ROOT, 'fixtures', name)} #{TMP} /e /r:1`
      else
        `rsync -av #{File.join(ROOT, 'fixtures', name)}/ #{TMP}/`
      end
      Dir.chdir TMP
      ENV['MM_ROOT'] = TMP
    end

    def no_file(name)
      FileUtils.rm name, force: true
    end

    def symlink(source, destination)
      no_file destination
      FileUtils.symlink File.expand_path(source),
                        File.expand_path(destination),
                        force: true
    end

    def file(name, content)
      file_path = File.join(TMP, name)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.open(file_path, 'w') do |file|
        file.write content
      end
    end

    def cleanup!
      Dir.chdir ROOT
      `rm -rf #{TMP}` if File.exist? TMP
    end
  end
end

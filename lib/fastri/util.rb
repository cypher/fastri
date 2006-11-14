# Copyright (C) 2006  Mauricio Fernandez <mfp@acm.org>

require 'rdoc/ri/ri_paths'
begin
  require 'rubygems'
rescue LoadError
end

require 'rdoc/ri/ri_writer'

module FastRI
module Util
  # Return an array of <tt>[name, version, path]</tt> arrays corresponding to
  # the last version of each installed gem. +path+ is the base path of the RI
  # documentation from the gem. If the version cannot be determined, it will
  # be +nil+, and the corresponding gem might be repeated in the output array
  # (once per version).
  def gem_directories_unique
    return [] unless defined? Gem
    gemdirs = Dir["#{Gem.path}/doc/*/ri"]
    gems = Hash.new{|h,k| h[k] = []}
    gemdirs.each do |path|
      gemname, version = %r{/([^/]+)-(.*)/ri$}.match(path).captures
      if gemname.nil? # doesn't follow any conventions :(
        gems[path[%r{/([^/]+)/ri$}, 1]] << [nil, path]
      else
        gems[gemname] << [version, path]
      end
    end
    gems.sort_by{|name, _| name}.map do |name, versions|
      version, path = versions.sort.last
      [name, version, File.expand_path(path)]
    end
  end
  module_function :gem_directories_unique

  # Return the <tt>[name, version, path]</tt> array for the gem owning the RI
  # information stored in +path+, or +nil+.
  def gem_info_for_path(path, gem_dir_info = FastRI::Util.gem_directories_unique)
    path = File.expand_path(path)
    matches = gem_dir_info.select{|name, version, gem_path| path.index(gem_path) == 0}
    matches.sort_by{|name, version, gem_path| [gem_path.size, version, name]}.last
  end
  module_function :gem_info_for_path

  # Return the +full_name+ (in ClassEntry or MethodEntry's sense) given a path
  # to a .yaml file relative to a "base RI DB path".
  def gem_relpath_to_full_name(relpath)
    case relpath
    when %r{^(.*)/cdesc-([^/]*)\.yaml$}
      path, name = $~.captures
      (path.split(%r{/})[0..-2] << name).join("::")
    when %r{^(.*)/([^/]*)-(i|c)\.yaml$}
      path, escaped_name, type = $~.captures
      name = RI::RiWriter.external_to_internal(escaped_name)
      sep = ( type == 'c' ) ? "." : "#"
      path.gsub("/", "::") + sep + name
    end
  end
  module_function :gem_relpath_to_full_name
  
  # Returns the home directory (win32-aware).
  def find_home
    # stolen from RubyGems
    ['HOME', 'USERPROFILE'].each do |homekey|
      return ENV[homekey] if ENV[homekey]
    end
    if ENV['HOMEDRIVE'] && ENV['HOMEPATH']
      return "#{ENV['HOMEDRIVE']}:#{ENV['HOMEPATH']}"
    end
    begin
      File.expand_path("~")
    rescue StandardError => ex
      if File::ALT_SEPARATOR
        "C:/"
      else
        "/"
      end
    end
  end
  module_function :find_home
end # module Util
end # module FastRI

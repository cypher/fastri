# Copyright (C) 2006  Mauricio Fernandez <mfp@acm.org>

require 'rdoc/ri/ri_paths'
begin
  require 'rubygems'
rescue LoadError
end

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
end # module Util
end # module FastRI

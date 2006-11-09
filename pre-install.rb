#!/usr/bin/env ruby

if /win/ =~ RUBY_PLATFORM and /darwin|cygwin/ !~ RUBY_PLATFORM
  require 'fileutils'
  %w[fri fastri-server ri-emacs].each do |fname|
    FileUtils.mv "bin/#{fname}", "bin/#{fname}.rb", :force => true
  end
end

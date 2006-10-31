# fastri-server.rb: serve RI documentation over DRb 
#
# Based on ri-emacs.rb by Kristof Bastiaensen <kristof@vleeuwen.org>
#
#    Copyright (C) 2004,2006 Kristof Bastiaensen
#                  2006      Mauricio Fernandez <mfp@acm.org>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#----------------------------------------------------------------------
#

require 'rdoc/ri/ri_paths'
require 'rdoc/ri/ri_cache'
require 'rdoc/ri/ri_util'
require 'rdoc/ri/ri_reader'
require 'rdoc/ri/ri_formatter'
require 'rdoc/ri/ri_display'

class DefaultDisplay
  def full_params(method)
    method.params.split(/\n/).each do |p|
      p.sub!(/^#{method.name}\(/o,'(')
      unless p =~ /\b\.\b/
        p = method.full_name + p
      end
      @formatter.wrap(p) 
      @formatter.break_to_newline
    end
  end
end

class StringRedirectedDisplay < DefaultDisplay
  attr_reader :stringio
  def initialize(*args)
    super(*args)
    reset_stringio
  end

  def puts(*a)
    @stringio.puts(*a)
  end

  def print(*a)
    @stringio.print(*a)
  end

  def reset_stringio
    @stringio = StringIO.new("")
    @formatter.stringio = @stringio
  end
end

class RedirectedFormatter < RI::TextFormatter
  attr_accessor :stringio
  def initialize(*options)
    super
    @stringio = StringIO.new("")
  end

  def puts(*a); @stringio.puts(*a) end
  def print(*a); @stringio.print(*a) end
end

class RIService
   Options = Struct.new(:formatter, :use_stdout, :width)

   def initialize(paths)
      options = Options.new

      options.use_stdout = true
      options.formatter = RedirectedFormatter
      options.width = 72

      begin
         require 'rubygems'
         Dir["#{Gem.path}/doc/*/ri"].each do |path|
            RI::Paths::PATH << path
         end
      rescue LoadError
      end 

      paths = paths || RI::Paths::PATH

      @ri_reader = RI::RiReader.new(RI::RiCache.new(paths))
      @display = StringRedirectedDisplay.new(options)
   end

   def lookup_keyw(keyw)
      begin
         @desc = NameDescriptor.new(keyw)
      rescue RiError => e
         return false
      end
      @namespaces = @ri_reader.top_level_namespace

      container = @namespaces
      for class_name in @desc.class_names
         return false if container.empty?
         @namespaces = @ri_reader.lookup_namespace_in(class_name, container)
         container = @namespaces.find_all {|m| m.name == class_name}
      end

      if @desc.method_name.nil?
         if [?., ?:, ?#].include? keyw[-1]
            @namespaces = container
            is_class_method = case keyw[-1]
                              when ?.: nil
                              when ?:: true
                              when ?#: false
                              end
            @methods = @ri_reader.find_methods("", is_class_method,
                                               container)
            return false if @methods.empty?
         else
            @namespaces = @namespaces.find_all{ |n| n.name.index(class_name).zero? }
            return false if @namespaces.empty?
            @methods = nil
         end
      else
         return false if container.empty?
         @namespaces = container
         @methods = @ri_reader.find_methods(@desc.method_name,
                                            @desc.is_class_method,
                                            container)
         @methods = @methods.find_all { |m|
            m.name.index(@desc.method_name).zero? }
         return false if @methods.empty?
      end
      
      return true
   end

   def completion_list(keyw)
      return @ri_reader.full_class_names if keyw == ""
      
      return nil unless lookup_keyw(keyw)

      if @methods.nil?
         return @namespaces.map{ |n| n.full_name }
      elsif @desc.class_names.empty?
         return @methods.map { |m| m.name }.uniq
      else
         return @methods.map { |m| m.full_name }
      end
   end

   def info(keyw)
      return nil unless lookup_keyw(keyw)
      
      if @methods.nil?
         @namespaces = @namespaces.find_all { |n| n.full_name == @desc.full_class_name }
         return nil if @namespaces.empty?
         klass = @ri_reader.get_class(@namespaces[0])
         capture_stdout { @display.display_class_info(klass, @ri_reader) }
      else
         @methods = @methods.find_all { |m| m.name == @desc.method_name }
         return nil if @methods.empty?
         meth = @ri_reader.get_method(@methods[0])
         capture_stdout { @display.display_method_info(meth) }
      end
   end

   def args(keyw)
      return nil unless lookup_keyw(keyw)
      return nil unless @desc.class_names.empty?

      @methods = @methods.find_all { |m| m.name == @desc.method_name }
      return nil if @methods.empty?
      sio = nil
      @methods.each do |m|
        meth = @ri_reader.get_method(m)
        sio = capture_stdout(false) { @display.full_params(meth) }
      end
      sio
   end

   # return a list of classes for the method keyw
   # return nil if keyw has already a class
   def class_list(keyw, rep='\1')
      return nil unless lookup_keyw(keyw)
      return nil unless @desc.class_names.empty?

      @methods = @methods.find_all { |m| m.name == @desc.method_name }

      return @methods.map{|m| m.full_name.sub(/(.*)(#|(::)).*/, rep) }.uniq
   end

   # flag means (#|::) 
   # return a list of classes and flag for the method keyw
   # return nil if keyw has already a class
   def class_list_with_flag(keyw)
     class_list(keyw, '\1\2')
   end

   private
   require "stringio"
   def capture_stdout(reset = true)
     @display.reset_stringio
     yield
     @display.stringio.string
   end
end

#{{{ Main program

if $0 == __FILE__

require 'rinda/ring'
require 'rinda/tuplespace'

class RiEmacs
  include DRbUndumped
end
DRb.start_service

service_ts = Rinda::TupleSpace.new
ring_server = Rinda::RingServer.new(service_ts)

service = RIService.new(nil)
provider = Rinda::RingProvider.new :FastRI, service, "FastRI documentation"
provider.provide

puts "I am #{Process.pid}"
Thread.new do 
  loop do
    GC.start
    sleep 300
  end
end

DRb.thread.join

end # main prog
# vi: set sw=2 expandtab:

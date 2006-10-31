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

FASTRI_VERSION = "0.0.1"

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
   QueryData = Struct.new(:desc, :namespaces, :methods)

   def self.untainted_copy(obj)
     obj.instance_eval{@display = nil}
     d = Marshal.dump(obj)
     d.untaint
     ret = Marshal.load(d)
     ret.instance_eval{ init_display }
     ret
   end

   def initialize(paths)
      begin
         require 'rubygems'
         Dir["#{Gem.path}/doc/*/ri"].each do |path|
            RI::Paths::PATH << path
         end
      rescue LoadError
      end 

      paths = paths || RI::Paths::PATH

      @ri_reader = RI::RiReader.new(RI::RiCache.new(paths))
      init_display
   end

   def init_display
      options = Options.new
      options.use_stdout = true
      options.formatter = RedirectedFormatter
      options.width = 72
      @display = StringRedirectedDisplay.new(options)
   end
   private :init_display

   def lookup_keyword(keyw)
     ret = QueryData.new
     begin
       ret.desc = NameDescriptor.new(keyw)
     rescue RiError => e
       return nil
     end
     ret.namespaces = @ri_reader.top_level_namespace

     container = ret.namespaces
     for class_name in ret.desc.class_names
       return nil if container.empty?
       ret.namespaces = @ri_reader.lookup_namespace_in(class_name, container)
       container = ret.namespaces.find_all {|m| m.name == class_name}
     end

      if ret.desc.method_name.nil?
         if [?., ?:, ?#].include? keyw[-1]
            ret.namespaces = container
            is_class_method = case keyw[-1]
                              when ?.: nil
                              when ?:: true
                              when ?#: false
                              end
            ret.methods = @ri_reader.find_methods("", is_class_method, container)
            return nil if ret.methods.empty?
         else
            ret.namespaces = ret.namespaces.find_all{ |n| n.name.index(class_name).zero? }
            return nil if ret.namespaces.empty?
            ret.methods = nil
         end
      else
         return nil if container.empty?
         ret.namespaces = container
         ret.methods = @ri_reader.find_methods(ret.desc.method_name,
                                               ret.desc.is_class_method,
                                               container)
         ret.methods = ret.methods.find_all do |m|
           m.name.index(ret.desc.method_name).zero?
         end
         return nil if ret.methods.empty?
      end
      
      ret
   end

   def completion_list(keyw)
      return @ri_reader.full_class_names if keyw == ""
      
      return nil unless (qdata = lookup_keyword(keyw))

      if qdata.methods.nil?
         return qdata.namespaces.map{ |n| n.full_name }
      elsif qdata.desc.class_names.empty?
         return qdata.methods.map { |m| m.name }.uniq
      else
         return qdata.methods.map { |m| m.full_name }
      end
   end

   def info(keyw)
      return nil unless (qdata = lookup_keyword(keyw))
      
      if qdata.methods.nil?
         qdata.namespaces = qdata.namespaces.find_all { |n| n.full_name == qdata.desc.full_class_name }
         return nil if qdata.namespaces.empty?
         klass = @ri_reader.get_class(qdata.namespaces[0])
         capture_stdout { @display.display_class_info(klass, @ri_reader) }
      else
         qdata.methods = qdata.methods.find_all { |m| m.name == qdata.desc.method_name }
         return nil if qdata.methods.empty?
         meth = @ri_reader.get_method(qdata.methods[0])
         capture_stdout { @display.display_method_info(meth) }
      end
   end

   def args(keyw)
      return nil unless (qdata = lookup_keyword(keyw))
      return nil unless qdata.desc.class_names.empty?

      qdata.methods = qdata.methods.find_all { |m| m.name == qdata.desc.method_name }
      return nil if qdata.methods.empty?
      sio = nil
      qdata.methods.each do |m|
        meth = @ri_reader.get_method(m)
        sio = capture_stdout(false) { @display.full_params(meth) }
      end
      sio
   end

   # return a list of classes for the method keyw
   # return nil if keyw has already a class
   def class_list(keyw, rep='\1')
      return nil unless (qdata = lookup_keyword(keyw))
      return nil unless qdata.desc.class_names.empty?

      qdata.methods = qdata.methods.find_all { |m| m.name == qdata.desc.method_name }

      return qdata.methods.map{|m| m.full_name.sub(/(.*)(#|(::)).*/, rep) }.uniq
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

require 'optparse'

options = {:allowed_hosts => ["localhost"], :addr => "127.0.0.1"}
OptionParser.new do |opts|
  opts.banner = "Usage: fastri-server.rb [options]"

  opts.on("-a", "--allow [HOST]", "Allow connections from HOST.",
          "(default: localhost)") do |host|
    options[:allowed_hosts] << host
  end

  opts.on("-s", "--bind [ADDR]", "Listen to connections on ADDR.",
          "(default: 127.0.0.1)") do |addr|
    options[:addr] = addr
  end

  opts.on("-h", "--help", "Show this help message") do 
    puts opts
    exit
  end
end.parse!

service = RIService.untainted_copy(RIService.new(nil))

require 'rinda/ring'
require 'rinda/tuplespace'
require 'drb/acl'

class RIService
  include DRbUndumped
end
acl_opt = ["deny", "all"]
options[:allowed_hosts].each{|host| acl_opt.concat ["allow", host.strip]}
acl = ACL.new(acl_opt)
DRb.install_acl(acl)

drb_addr = "druby://#{options[:addr]}:0"
DRb.start_service(drb_addr)

$SAFE = 1
service_ts = Rinda::TupleSpace.new
ring_server = Rinda::RingServer.new(service_ts)

provider = Rinda::RingProvider.new :FastRI, service, "FastRI documentation"
provider.provide

require 'enumerator'
puts "FastRI #{FASTRI_VERSION} listening on #{DRb.uri}"
puts "ACL:"
acl_opt.each_slice(2){|action, host| puts "%-5s %s" % [action, host]}

# GC periodically
# keeps the process hot too :)
Thread.new do 
  loop do
    GC.start
    sleep 300
  end
end

DRb.thread.join

end # main prog
# vi: set sw=2 expandtab:

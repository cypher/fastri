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
 
require 'rdoc/ri/ri_paths'
require 'rdoc/ri/ri_util'
require 'rdoc/ri/ri_formatter'
require 'rdoc/ri/ri_display'

require 'fastri/ri_index.rb'

module FastRI

class ::DefaultDisplay
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

class StringRedirectedDisplay < ::DefaultDisplay
  attr_reader :stringio, :formatter
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

class ::RI::TextFormatter
  def puts(*a); @stringio.puts(*a) end
  def print(*a); @stringio.print(*a) end
end

module FormatterRedirection
  attr_accessor :stringio
  def initialize(*options)
    @stringio = StringIO.new("")
    super
  end
end

class RedirectedAnsiFormatter < RI::AnsiFormatter
  include FormatterRedirection
end

class RedirectedTextFormatter < RI::TextFormatter
  include FormatterRedirection
end

class RiService
  Options = Struct.new(:formatter, :use_stdout, :width)
  QueryData = Struct.new(:desc, :namespaces, :methods)

  def initialize(ri_reader)
    @ri_reader = ri_reader
  end

  def obtain_entries(descriptor, try_partial = true)
    if descriptor.class_names.empty?
      meths = @ri_reader.methods_under_matching("", /(#|\.)#{descriptor.method_name}$/, true)
      return meths unless meths.empty?
      return [] unless try_partial
      # try with partial matches: foo -> foobar, foobaz    anywhere in the
      # hierarchy
      meths = @ri_reader.methods_under_matching("", /(#|\.)#{descriptor.method_name}/, true)
      return meths
    end

    # if we're here, some namespace was given
    full_ns_name = descriptor.class_names.join("::")
    if descriptor.method_name == nil
      ns = @ri_reader.get_class_entry(full_ns_name)
      return [ns] if ns
      # nested namespace
      namespaces = @ri_reader.namespaces_under_matching("", /::#{full_ns_name}$/, true)
      return namespaces unless namespaces.empty?
      return [] unless try_partial
      # partial match
      namespaces = @ri_reader.namespaces_under_matching("", /^#{full_ns_name}/, false)
      return namespaces unless namespaces.empty?
      # partial and nested
      namespaces = @ri_reader.namespaces_under_matching("", /::#{full_ns_name}[^:]*$/, true)
      return namespaces
    else  # both namespace and method
      seps = separators(descriptor.is_class_method)
      seps.each do |sep|
        entry = @ri_reader.get_method_entry("#{full_ns_name}#{sep}#{descriptor.method_name}")
        return [entry] if entry
      end
      # no exact matches
      sep_re = "(" + seps.map{|x| Regexp.escape(x)}.join("|") + ")"
      # nested
      methods = @ri_reader.methods_under_matching("", /::#{full_ns_name}#{sep_re}#{descriptor.method_name}$/, true)
      return methods unless methods.empty?

      return [] unless try_partial
      # partial
      methods = @ri_reader.methods_under_matching(full_ns_name, /#{sep_re}#{descriptor.method_name}/, false)
      return methods unless methods.empty?
      # partial and nested
      methods = @ri_reader.methods_under_matching("", /::#{full_ns_name}#{sep_re}#{descriptor.method_name}/, true)
      return methods
    end
  end

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

    descriptor = NameDescriptor.new(keyw)
  
    if descriptor.class_names.empty?
      # try partial matches
      meths = @ri_reader.methods_under_matching("", /(#|\.)#{descriptor.method_name}/, true)
      ret = meths.map{|x| x.name}.uniq.sort
      return ret.empty? ? nil : ret
    end

    # if we're here, some namespace was given
    full_ns_name = descriptor.class_names.join("::")
    if descriptor.method_name == nil && ! [?#, ?:, ?.].include?(keyw[-1])
      # partial match
      namespaces = @ri_reader.namespaces_under_matching("", /^#{full_ns_name}/, false)
      ret = namespaces.map{|x| x.full_name}.uniq.sort
      return ret.empty? ? nil : ret
    else
      if [?#, ?:, ?.].include?(keyw[-1])
        seps = case keyw[-1]
          when ?#; %w[#]
          when ?:; %w[.]
          when ?.; %w[. #]
        end
      else  # both namespace and method
        seps = separators(descriptor.is_class_method)
      end
      sep_re = "(" + seps.map{|x| Regexp.escape(x)}.join("|") + ")"
      # partial
      methods = @ri_reader.methods_under_matching(full_ns_name, /#{sep_re}#{descriptor.method_name}/, false)
      ret = methods.map{|x| x.full_name}.uniq.sort
      return ret.empty? ? nil : ret
    end
  rescue RiError
    return nil
  end

  def info(keyw, type = :ansi)
    return nil if keyw.strip.empty?
    descriptor = NameDescriptor.new(keyw)
    entries = obtain_entries(descriptor, true)

    case entries.size
    when 0; nil
    when 1
      case entries[0]    #FIXME: should be done by the entry itself
      when RiIndex::ClassEntry
        capture_stdout(display(type)) do |display|
          display.display_class_info(@ri_reader.get_class(entries[0]), @ri_reader)
        end
      when RiIndex::MethodEntry
        capture_stdout(display(type)) do |display|
          display.display_method_info(@ri_reader.get_method(entries[0]))
        end
      end
    else
      capture_stdout(display(type)) do |display|
        formatter = display.formatter
        formatter.draw_line("Multiple choices:")
        formatter.blankline
        formatter.wrap(entries.map{|x| x.full_name}.join(", "))
      end
    end
  rescue RiError
    return nil
  end

  def args(keyw, type = :ansi)
    return nil unless (qdata = lookup_keyword(keyw))
    return nil unless qdata.desc.class_names.empty?

    qdata.methods = qdata.methods.find_all { |m| m.name == qdata.desc.method_name }
    return nil if qdata.methods.empty?
    params_text = ""
    qdata.methods.each do |m|
      meth = @ri_reader.get_method(m)
      params_text << capture_stdout(display(type)) do |display|
        display.full_params(meth)
      end
    end
    params_text
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

  def separators(is_class_method)
    case is_class_method
    when true;  ["."]
    when false; ["#"]
    when nil;   [".","#"]
    end
  end
  def display(type)
    options = Options.new
    options.use_stdout = true
    case type.to_sym
    when :ansi
      options.formatter = RedirectedAnsiFormatter
    else
      options.formatter = RedirectedTextFormatter
    end
    options.width = 72
    StringRedirectedDisplay.new(options)
  end

  def capture_stdout(display)
    yield display
    display.stringio.string
  end
end

end # module FastRI

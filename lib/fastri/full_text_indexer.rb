# Copyright (C) 2006  Mauricio Fernandez <mfp@acm.org>
#

module FastRI

class FullTextIndexer
  WORD_RE    = /[A-Za-z0-9_]+/
  NONWORD_RE = /[^A-Za-z0-9_]+/

  def initialize(max_querysize)
    @documents = []
    @doc_hash  = {}
    @max_wordsize = max_querysize
  end

  def add_document(name, data)
    @doc_hash[name] = data
    @documents << name
  end

  def data(name)
    @doc_hash[name]
  end

  def documents
    @documents = @documents.uniq
  end

  def escape_text(str)
    str = str.gsub(/\|/,"||")
    str.gsub!(/</,"|<")
    str
  end

  def unescape_text(str)
    str = str.gsub(/\|\|/, "|")
    str.gsub!(/\|</, "<")
    str
  end

  def preprocess(str)
    str.gsub(/>>>>|<<<</,"")
  end

  require 'strscan'
  def find_suffixes(text, offset)
    find_suffixes_simple(text, WORD_RE, NONWORD_RE, offset)
  end

  def find_suffixes_simple(string, word_re, nonword_re, offset)
    suffixes = []
    sc = StringScanner.new(string)
    until sc.eos?
      sc.skip(nonword_re)
      len = string.size
      loop do
        break if sc.pos == len
        suffixes << offset + sc.pos
        skipped_word = sc.skip(word_re)
        break unless skipped_word
        loop do
          skipped_nonword = sc.skip(nonword_re)
          break unless skipped_nonword
        end
      end
    end
    suffixes
  end

  require 'enumerator'
  def build_index(full_text_IO, suffix_array_IO)
    fulltext = ""
    io = StringIO.new(fulltext)
    documents.each do |doc|
      io.write(@doc_hash[doc])
      full_text_IO.write(@doc_hash[doc])
      footer = "<<<<#{escape_text(doc)}>>>>"
      io.write(footer)
      full_text_IO.write(footer)
    end

    scanner = StringScanner.new(fulltext)

    count = 0
    suffixes = []
    until scanner.eos?
      count += 1
      start = scanner.pos
      text = scanner.scan_until(/<<<<.*?>>>>/)
      text = text.sub(/<<<<.*?>>>>$/,"")
      suffixes.concat find_suffixes(text, start)
      scanner.terminate if !text
    end
    sorted = suffixes.sort_by{|x| fulltext[x, @max_wordsize]}
    sorted.each_slice(10000){|x| suffix_array_IO.write x.pack("V*")}
    nil
  end
end # class FullTextIndexer

end # module FastRI

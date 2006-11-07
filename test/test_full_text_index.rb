require 'test/unit'
$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
$:.unshift "lib"
require 'fastri/full_text_index'

class TestFullTextIndex < Test::Unit::TestCase
  require 'stringio'
  include FastRI

  DATA = <<EOF
this is a test <<<<foo.txt>>>>zzzz<<<<bar.txt>>>>
EOF
  SUFFIXES = [8, 5, 10, 0, 30].map{|x| [x].pack("V")}.join("")

  def setup
    @index = FullTextIndex.new_from_ios(StringIO.new(DATA), StringIO.new(SUFFIXES))
  end

  def test_new_from_ios
    a = nil
    assert_nothing_raised { a = FullTextIndex.new_from_ios(StringIO.new(DATA), StringIO.new(SUFFIXES)) }
    assert_equal(FullTextIndex::DEFAULT_OPTIONS[:max_query_size], a.max_query_size)
  end
  
  def test_lookup_basic
    %w[this is a test].each do |term|
      result = @index.lookup(term)
      assert_kind_of(FullTextIndex::Result, result)
      assert_equal(term, result.query)
      assert_equal("foo.txt", result.path)
    end
    assert_equal(0, @index.lookup("a").index)
    assert_equal(2, @index.lookup("t").index)
    assert_equal(3, @index.lookup("th").index)

    assert_equal(4, @index.lookup("z").index)
    assert_equal("bar.txt", @index.lookup("z").path)
  end

  def test_Result_text
    assert_equal("t", @index.lookup("this").text(1))
    assert_equal("this", @index.lookup("this").text(4))
    assert_equal("this is a ", @index.lookup("this").text(10))
    assert_equal("this is a test ", @index.lookup("th").text(100))

    assert_equal("z", @index.lookup("z").text(1))
    assert_equal("zzzz", @index.lookup("z").text(10))
  end

  def test_Result_context
    assert_equal(" a ", @index.lookup("a").context(1))
    assert_equal("s a t", @index.lookup("a").context(2))
    assert_equal("is a te", @index.lookup("a").context(3))
    assert_equal("s is a test", @index.lookup("a").context(5))
    assert_equal("this is a test ", @index.lookup("a").context(10))
  end

  def test_Result_context_non_initial_entry
    assert_equal("zz", @index.lookup("z").context(1))
    assert_equal("zzz", @index.lookup("z").context(2))
    assert_equal("zzzz", @index.lookup("z").context(3))
    assert_equal("zzzz", @index.lookup("z").context(4))
    assert_equal("zzzz", @index.lookup("z").context(10))
  end

  def test_lookup_nonexistent
    assert_nil(@index.lookup("bogus"))
  end

end

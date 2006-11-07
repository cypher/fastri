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

  DATA2 = <<EOF
this is a test <<<<foo.txt>>>>zzzz this<<<<bar.txt>>>>
EOF
  SUFFIXES2 = [8, 5, 10, 35, 0, 30].map{|x| [x].pack("V")}.join("")

  def setup
    @index = FullTextIndex.new_from_ios(StringIO.new(DATA), StringIO.new(SUFFIXES))
    @index2 = FullTextIndex.new_from_ios(StringIO.new(DATA2), StringIO.new(SUFFIXES2))
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

    assert_equal("test ", @index.lookup("t").text(10))
    assert_equal("test ", @index.lookup("t").text(20))

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

  def test_next_match_basic
    first = @index2.lookup("t")
    assert_equal("foo.txt", first.path)
    assert_equal(2, first.index)
    assert_equal("test ", first.text(10))

    second = @index2.next_match(first)
    assert_equal("bar.txt", second.path)
    assert_equal(3, second.index)
    assert_equal("this", second.text(10))

    third = @index2.next_match(second)
    assert_kind_of(FullTextIndex::Result, third)
    assert_equal(4, third.index)
    assert_equal("this is a ", third.text(10))

    assert_nil(@index2.next_match(third))
  end

  def test_next_match_restricted
    first = @index2.lookup("t")
    assert_equal("foo.txt", first.path)
    assert_equal(2, first.index)
    assert_equal("test ", first.text(10))

    second = @index2.next_match(first, "this is")
    assert_equal("foo.txt", second.path)
    assert_equal(4, second.index)
    assert_equal("this is a ", second.text(10))

    assert_nil(@index2.next_match(first, "foo"))
  end

  def test_next_match_regexp
    first = @index2.lookup("t")
    assert_equal("foo.txt", first.path)
    assert_equal(2, first.index)
    assert_equal("test ", first.text(10))

    second = @index2.next_match(first, /.*test/)
    assert_equal("foo.txt", second.path)
    assert_equal(4, second.index)
    assert_equal("this is a test ", second.text(20))
  end


  def test_next_matches
    first = @index2.lookup("t")
    all = [first] + @index2.next_matches(first)
    assert_equal([2, 3, 4], all.map{|x| x.index})
    assert_equal(["foo.txt", "bar.txt", "foo.txt"], all.map{|x| x.path})
    one, two, three = *all
    assert_equal(["test ", "this", "this is a test "], all.map{|x| x.text(20)})
  end

  def test_next_matches_restricted
    first = @index2.lookup("t")
    assert_equal([], @index2.next_matches(first, "this is not"))
    all = @index2.next_matches(first, "this is")
    assert_equal(["foo.txt"], all.map{|x| x.path})
    assert_equal([4], all.map{|x| x.index})
    assert_equal(["this is a test "], all.map{|x| x.text(20)})
  end

  def test_next_matches_regexp
    first = @index2.lookup("t")
    all = @index2.next_matches(first, /.*test/)
    assert_equal(["foo.txt"], all.map{|x| x.path})
    assert_equal([4], all.map{|x| x.index})
    assert_equal(["this is a test "], all.map{|x| x.text(20)})
  end

end

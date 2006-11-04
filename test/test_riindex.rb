require 'test/unit'
$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
$:.unshift "lib"
require 'fastri/ri_index'

class Test_RIIndex < Test::Unit::TestCase
  INDEX_DATA =<<EOF
#{FastRI::RIIndex::MAGIC}
Sources:
system                          /usr/share/ri/system/
somegem-0.1.0                   /long/path/somegem-0.1.0
stuff-1.1.0                     /long/path/stuff-1.1.0
================================================================================
Namespaces:
ABC 0 1
ABC::DEF 0 1
ABC::DEF::Foo 1
ABC::Zzz 0
CDE 1 2
FGH 2
FGH::Adfdsf 2
================================================================================
Methods:
ABC::DEF.bar 0
ABC::DEF::Foo#baz 1
ABC::DEF::Foo#foo 1
ABC::Zzz.foo 0 1
ABC::Zzz#foo 0
CDE.foo 1 2
FGH::Adfdsf#foo 2
================================================================================
EOF

  require 'stringio'
  def setup
    @index = FastRI::RIIndex.new_from_IO(StringIO.new(INDEX_DATA))
  end

  def test_dump
    s = StringIO.new("")
    @index.dump(s)
    assert_equal(INDEX_DATA, s.string)
  end

  def test_toplevel_namespace
    ret = @index.top_level_namespace
    assert_kind_of(Array, ret)
    assert_kind_of(FastRI::RIIndex::TopLevelEntry, ret[0])
  end

  def test_full_class_names
    assert_equal(["ABC", "ABC::DEF", "ABC::DEF::Foo", "ABC::Zzz", "CDE", "FGH", "FGH::Adfdsf"], @index.full_class_names)
    assert_equal(["ABC", "ABC::DEF", "ABC::Zzz"], @index.full_class_names(0))
    assert_equal(["ABC", "ABC::DEF", "ABC::DEF::Foo", "CDE"], @index.full_class_names(1))
    assert_equal(["CDE", "FGH", "FGH::Adfdsf"], @index.full_class_names(2))
    assert_equal(["CDE", "FGH", "FGH::Adfdsf"], @index.full_class_names("stuff-1.1.0"))
    assert_equal([], @index.full_class_names("nonexistent-1.1.0"))
  end

  def test_full_method_names
    assert_equal(["ABC::DEF.bar", "ABC::DEF::Foo#baz", "ABC::DEF::Foo#foo", 
                 "ABC::Zzz.foo", "ABC::Zzz#foo", "CDE.foo", "FGH::Adfdsf#foo"], 
                 @index.full_method_names)
    assert_equal(["ABC::DEF.bar", "ABC::Zzz.foo", "ABC::Zzz#foo"], 
                 @index.full_method_names(0))
    assert_equal(["ABC::DEF::Foo#baz", "ABC::DEF::Foo#foo", "ABC::Zzz.foo", "CDE.foo"], 
                 @index.full_method_names(1))
    assert_equal(["CDE.foo", "FGH::Adfdsf#foo"], @index.full_method_names(2))
    assert_equal(["CDE.foo", "FGH::Adfdsf#foo"], @index.full_method_names("stuff-1.1.0"))
    assert_equal([], @index.full_method_names("nonexistent-1.1.0"))
  end

  def test_all_names
    assert_equal(["ABC", "ABC::DEF", "ABC::DEF::Foo", "ABC::Zzz", "CDE", "FGH", 
                 "FGH::Adfdsf", "ABC::DEF.bar", "ABC::DEF::Foo#baz", 
                 "ABC::DEF::Foo#foo", "ABC::Zzz.foo", "ABC::Zzz#foo", 
                 "CDE.foo", "FGH::Adfdsf#foo"], @index.all_names)
    assert_equal(["ABC", "ABC::DEF", "ABC::Zzz", "ABC::DEF.bar", 
                 "ABC::Zzz.foo", "ABC::Zzz#foo"], @index.all_names(0))
    assert_equal(["ABC", "ABC::DEF", "ABC::DEF::Foo", "CDE", 
                 "ABC::DEF::Foo#baz", "ABC::DEF::Foo#foo", "ABC::Zzz.foo",
                 "CDE.foo"], @index.all_names(1))
    assert_equal(["CDE", "FGH", "FGH::Adfdsf", "CDE.foo", "FGH::Adfdsf#foo"],
                 @index.all_names(2))
    assert_equal(["ABC", "ABC::DEF", "ABC::DEF::Foo", "CDE", 
                 "ABC::DEF::Foo#baz", "ABC::DEF::Foo#foo", "ABC::Zzz.foo",
                 "CDE.foo"], @index.all_names("somegem-0.1.0"))
    assert_equal([], @index.all_names("notinstalled-1.0"))
  end

  def test_namespaces_under
    assert_kind_of(Array, @index.namespaces_under("ABC", true, nil))
    results = @index.namespaces_under("ABC", true, nil)
    assert_equal(3, results.size)
    assert_equal(["ABC::DEF", "ABC::DEF::Foo", "ABC::Zzz"], results.map{|x| x.full_name})
    results = @index.namespaces_under("ABC", false, nil)
    assert_equal(2, results.size)
    assert_equal(["ABC::DEF", "ABC::Zzz"], results.map{|x| x.full_name})
  end

  def test_namespaces_under_scoped
    results = @index.namespaces_under("ABC", false, 1)
    assert_kind_of(Array, results)
    assert_equal(["ABC::DEF"], results.map{|x| x.full_name})
    results = @index.namespaces_under("ABC", true, 1)
    assert_equal(2, results.size)
    assert_equal(["ABC::DEF", "ABC::DEF::Foo"], results.map{|x| x.full_name})
    results = @index.namespaces_under("ABC", true, "somegem-0.1.0")
    assert_equal(2, results.size)
    assert_equal(["ABC::DEF", "ABC::DEF::Foo"], results.map{|x| x.full_name})
    results = @index.namespaces_under("ABC", true, 0)
    assert_equal(2, results.size)
    assert_equal(["ABC::DEF", "ABC::Zzz"], results.map{|x| x.full_name})
  end

  def test_namespaces_under_toplevel
    toplevel = @index.top_level_namespace[0]
    assert_equal(["ABC", "CDE", "FGH"], 
                 @index.namespaces_under(toplevel, false, nil).map{|x| x.full_name})
    assert_equal(["ABC", "ABC::DEF", "ABC::DEF::Foo", "ABC::Zzz", 
                  "CDE", "FGH", "FGH::Adfdsf"], 
                 @index.namespaces_under(toplevel, true, nil).map{|x| x.full_name})
    assert_equal(["CDE", "FGH", "FGH::Adfdsf"], 
                 @index.namespaces_under(toplevel, true, "stuff-1.1.0").map{|x| x.full_name})
  end

  def test_methods_under_scoped
    results = @index.methods_under("ABC", true, 1)
    assert_equal(["ABC::DEF::Foo#baz", "ABC::DEF::Foo#foo", "ABC::Zzz.foo"], results.map{|x| x.full_name})
    results = @index.methods_under("CDE", false, "stuff-1.1.0")
    assert_equal(["CDE.foo"], results.map{|x| x.full_name})
    results = @index.methods_under("ABC", true, nil)
    assert_equal(["ABC::DEF.bar", "ABC::DEF::Foo#baz", "ABC::DEF::Foo#foo", 
                 "ABC::Zzz.foo", "ABC::Zzz#foo"], results.map{|x| x.full_name})
    assert_equal(["ABC::DEF.bar", "ABC::DEF::Foo#baz", "ABC::DEF::Foo#foo", 
                 "ABC::Zzz.foo", "ABC::Zzz#foo", "CDE.foo", "FGH::Adfdsf#foo"], 
                 @index.methods_under("", true, nil).map{|x| x.full_name})
    assert_equal([], @index.methods_under("ABC", false, nil).map{|x| x.full_name})
    assert_equal(["CDE.foo"], 
                 @index.methods_under("CDE", false, nil).map{|x| x.full_name})
    assert_equal(["FGH::Adfdsf#foo"], 
                 @index.methods_under("FGH", true, nil).map{|x| x.full_name})
    assert_equal([], @index.methods_under("FGH", true, 0).map{|x| x.full_name})
    assert_equal(["FGH::Adfdsf#foo"], 
                 @index.methods_under("FGH", true, 2).map{|x| x.full_name})
    assert_equal([], @index.methods_under("FGH", false, 2).map{|x| x.full_name})
    assert_equal(["FGH::Adfdsf#foo"], 
                 @index.methods_under("FGH::Adfdsf", false, 2).map{|x| x.full_name})
    assert_equal(["FGH::Adfdsf#foo"], 
                 @index.methods_under("FGH::Adfdsf", true, 2).map{|x| x.full_name})
    assert_equal([], @index.methods_under("FGH::Adfdsf", false, 0).map{|x| x.full_name})
  end

  def test_lookup_namespace_in
    toplevel = @index.top_level_namespace
    res = @index.lookup_namespace_in("ABC", toplevel)
    assert_equal(["ABC"], res.map{|x| x.full_name})
    toplevel2 = @index.top_level_namespace(2)
    assert_equal([], @index.lookup_namespace_in("ABC", toplevel2))
    assert_equal(["FGH"], @index.lookup_namespace_in("FGH", toplevel2).map{|x| x.full_name})
  end

  def test_classentry_contained_modules_matching
    toplevel = @index.top_level_namespace[0]
    assert_equal(["ABC"], toplevel.contained_modules_matching("ABC").map{|x| x.full_name})
  end
end

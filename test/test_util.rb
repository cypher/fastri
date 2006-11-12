# Copyright (C) 2006  Mauricio Fernandez <mfp@acm.org>
#

require 'test/unit'
$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
$:.unshift "lib"
require 'fastri/util'

class TestUtil < Test::Unit::TestCase
  data = <<EOF
foo 0.1.1 /usr/local/lib/ruby/gems/1.8/doc/foo-0.1.1/ri
foo 1.1.1 /usr/local/lib/ruby/gems/1.8/doc/foo-1.1.1/ri
bar 0.1.1 /usr/local/lib/ruby/gems/1.8/doc/bar-0.1.1/ri
baz 0.1.1 /usr/local/lib/ruby/gems/1.8/doc/baz-0.1.1/ri
EOF
  GEM_DIR_INFO = data.split(/\n/).map{|l| l.split(/\s+/)}

  include FastRI::Util
  def test_gem_info_for_path
    assert_equal(["foo", "0.1.1", "/usr/local/lib/ruby/gems/1.8/doc/foo-0.1.1/ri"],
                 gem_info_for_path("/usr/local/lib/ruby/gems/1.8/doc/foo-0.1.1/ri/Array/cdesc-Array.yaml", GEM_DIR_INFO))
    assert_equal(["foo", "1.1.1", "/usr/local/lib/ruby/gems/1.8/doc/foo-1.1.1/ri"],
                 gem_info_for_path("/usr/local/lib/ruby/gems/1.8/doc/foo-1.1.1/ri/Array/cdesc-Array.yaml", GEM_DIR_INFO))
    assert_equal(["bar", "0.1.1", "/usr/local/lib/ruby/gems/1.8/doc/bar-0.1.1/ri"],
                 gem_info_for_path("/usr/local/lib/ruby/gems/1.8/doc/bar-0.1.1/ri/Array/cdesc-Array.yaml", GEM_DIR_INFO))
    assert_equal(["baz", "0.1.1", "/usr/local/lib/ruby/gems/1.8/doc/baz-0.1.1/ri"],
                 gem_info_for_path("/usr/local/lib/ruby/gems/1.8/doc/baz-0.1.1/ri/Array/cdesc-Array.yaml", GEM_DIR_INFO))
    assert_nil(gem_info_for_path("/usr/lib/ruby/gems/1.8/doc/baz-1.1.1/ri/Array/cdesc-Array.yaml", GEM_DIR_INFO))
  end
end

require 'helper'

class SlopTest < TestCase

  def build_option(*args)
    opt = Slopt.new.send(:build_option, args)
    config = opt.config.reject { |k, v| v == Slopt::Option::DEFAULT_OPTIONS[k] }
    [opt.short, opt.long, opt.description, config]
  end

  def temp_argv(items)
    old_argv = ARGV.clone
    ARGV.replace items
    yield
  ensure
    ARGV.replace old_argv
  end

  def temp_stdout
    $stdout = StringIO.new
    yield $stdout.string
  ensure
    $stdout = STDOUT
  end

  test "includes Enumerable" do
    assert_includes Slopt.included_modules, Enumerable
  end

  test "enumerates Slopt::Option objects in #each" do
    Slopt.new { on :f; on :b; }.each { |o| assert_kind_of Slopt::Option, o }
  end

  test "build_option" do
    assert_equal ['f', nil, nil, {}], build_option(:f)
    assert_equal [nil, 'foo', nil, {}], build_option(:foo)
    assert_equal ['f', nil, 'Some description', {}], build_option(:f, 'Some description')
    assert_equal ['f', 'foo', nil, {}], build_option(:f, :foo)
    assert_equal [nil, '1.8', 'Use v. 1.8', {}], build_option('--1.8', 'Use v. 1.8')

    # with arguments
    assert_equal ['f', nil, nil, {:argument=>true}], build_option('f=')
    assert_equal [nil, 'foo', nil, {:argument=>true}], build_option('foo=')
    assert_equal [nil, 'foo', nil, {:optional_argument=>true}], build_option('foo=?')
  end

  test "parsing option=value" do
    slop = Slopt.new { on :foo= }
    slop.parse %w' --foo=bar '
    assert_equal 'bar', slop[:foo]

    slop = Slopt.new(:multiple_switches => false) { on :f=; on :b= }
    slop.parse %w' -fabc -bdef '
    assert_equal 'abc', slop[:f]
    assert_equal 'def', slop[:b]
  end

  test "fetch_option" do
    slop = Slopt.new
    opt1 = slop.on :f, :foo
    opt2 = slop.on :bar

    assert_equal opt1, slop.fetch_option(:foo)
    assert_equal opt1, slop.fetch_option(:f)
    assert_equal opt2, slop.fetch_option(:bar)
    assert_equal opt2, slop.fetch_option('--bar')
    assert_nil slop.fetch_option(:baz)
  end

  test "default all options to take arguments" do
    slop = Slopt.new(:arguments => true)
    opt1 = slop.on :foo
    opt2 = slop.on :bar, :argument => false

    assert opt1.expects_argument?
    refute opt2.expects_argument?
  end

  test "extract_option" do
    slop = Slopt.new
    extract = proc { |flag| slop.send(:extract_option, flag) }
    slop.on :opt=

    assert_kind_of Array, extract['--foo']
    assert_equal 'bar', extract['--foo=bar'][1]
    assert_equal 'bar', extract['-f=bar'][1]
    assert_nil extract['--foo'][0]
    assert_kind_of Slopt::Option, extract['--opt'][0]
    assert_equal false, extract['--no-opt'][1]
  end

  test "non-options yielded to parse()" do
    foo = nil
    slop = Slopt.new
    slop.parse ['foo'] do |x| foo = x end
    assert_equal 'foo', foo
  end

  test "::parse returns a Slopt object" do
    assert_kind_of Slopt, Slopt.parse([])
  end

  test "parse" do
    slop = Slopt.new
    assert_equal ['foo'], slop.parse(%w'foo')
    assert_equal ['foo'], slop.parse!(%w'foo')
  end

  test "parse!" do
    slop = Slopt.new { on :foo= }
    assert_equal [], slop.parse!(%w'--foo bar')
    slop = Slopt.new {  on :baz }
    assert_equal ['etc'], slop.parse!(%w'--baz etc')
  end

  test "new() accepts a hash of configuration options" do
    slop = Slopt.new(:foo => :bar)
    assert_equal :bar, slop.config[:foo]
  end

  test "defaulting to ARGV" do
    temp_argv(%w/--name lee/) do
      opts = Slopt.parse { on :name= }
      assert_equal 'lee', opts[:name]
    end
  end

  test "automatically adding the help option" do
    slop = Slopt.new :help => true
    refute_empty slop.options
    assert_equal 'Display this help message.', slop.options.first.description
  end

  test "default help exits" do
    temp_stdout do
      slop = Slopt.new :help => true
      assert_raises SystemExit do
        slop.parse %w/--help/
      end
    end
  end

  test "indent in help" do
    slop = Slopt.new :indent => 2, :banner => false do
      on :f
    end
    assert_equal "  -f,         ", slop.help

    slop = Slopt.new :indent => 2, :banner => false do
      on :f, :foo
    end
    assert_equal "  -f, --foo      ", slop.help
  end

  test ":arguments and :optional_arguments config options" do
    slop = Slopt.new(:arguments => true) { on :foo }
    assert slop.fetch_option(:foo).expects_argument?

    slop = Slopt.new(:optional_arguments => true) { on :foo }
    assert slop.fetch_option(:foo).accepts_optional_argument?
  end

  test "yielding non-options when a block is passed to parse()" do
    items = []
    opts = Slopt.new { on :name= }
    opts.parse(%w/--name lee a b c/) { |v| items << v }
    assert_equal ['a', 'b', 'c'], items
  end

  test "on empty callback" do
    opts = Slopt.new
    foo = nil
    opts.add_callback(:empty) { foo = "bar" }
    opts.parse []
    assert_equal "bar", foo
  end

  test "on no_options callback" do
    opts = Slopt.new
    foo = nil
    opts.add_callback(:no_options) { foo = "bar" }
    opts.parse %w( --foo --bar etc hello )
    assert_equal "bar", foo
  end

  test "to_hash()" do
    opts = Slopt.new { on :foo=; on :bar; on :baz; on :zip }
    opts.parse(%w'--foo hello --no-bar --baz')
    assert_equal({ :foo => 'hello', :bar => false, :baz => true, :zip => nil }, opts.to_hash)
  end

  test "missing() returning all missing option keys" do
    opts = Slopt.new { on :foo; on :bar }
    opts.parse %w'--foo'
    assert_equal ['bar'], opts.missing
  end

  test "autocreating options" do
    opts = Slopt.new :autocreate => true
    opts.parse %w[ --foo bar --baz ]
    assert opts.fetch_option(:foo).expects_argument?
    assert opts.fetch_option(:foo).autocreated?
    assert_equal 'bar', opts.fetch_option(:foo).value
    refute opts.fetch_option(:baz).expects_argument?
    assert_equal nil, opts.fetch_option(:bar)

    opts = Slopt.new :autocreate => true do
      on :f, :foo=
    end
    opts.parse %w[ --foo bar --baz stuff ]
    assert_equal 'bar', opts[:foo]
    assert_equal 'stuff', opts[:baz]
  end

  test "option terminator" do
    opts = Slopt.new { on :foo= }
    items = %w' foo -- --foo bar '
    opts.parse! items
    assert_equal %w' foo --foo bar ', items
  end

  test "raising an InvalidArgumentError when the argument doesn't match" do
    opts = Slopt.new { on :foo=, :match => /^[a-z]+$/ }
    assert_raises(Slopt::InvalidArgumentError) { opts.parse %w' --foo b4r '}
  end

  test "raising a MissingArgumentError when the option expects an argument" do
    opts = Slopt.new { on :foo= }
    assert_raises(Slopt::MissingArgumentError) { opts.parse %w' --foo '}
  end

  test "raising a MissingOptionError when a required option is missing" do
    opts = Slopt.new { on :foo, :required => true }
    assert_raises(Slopt::MissingOptionError) { opts.parse %w'' }
  end

  test "raising InvalidOptionError when strict mode is enabled and an unknown option appears" do
    opts = Slopt.new :strict => true
    assert_raises(Slopt::InvalidOptionError) { opts.parse %w'--foo' }
    assert_raises(Slopt::InvalidOptionError) { opts.parse %w'-fabc' }
  end

  test "raising InvalidOptionError for multiple short options" do
    opts = Slopt.new :strict => true
    opts.on :L
    assert_raises(Slopt::InvalidOptionError) { opts.parse %w'-Ly' }

    # but not with no strict mode!
    opts = Slopt.new
    opts.on :L
    assert opts.parse %w'-Ly'
  end

  test "multiple_switches is enabled by default" do
    opts = Slopt.new { on :f; on :b }
    opts.parse %w[ -fb ]
    assert opts.present?(:f)
    assert opts.present?(:b)
  end

  test "multiple_switches disabled" do
    opts = Slopt.new(:multiple_switches => false) { on :f= }
    opts.parse %w[ -fabc123 ]
    assert_equal 'abc123', opts[:f]
  end

  test "muiltiple_switches should not trash arguments" do
    opts = Slopt.new{ on :f; on :b }
    args = opts.parse!(%w'-fb foo')
    assert_equal %w'foo', args
  end

  test "multiple options should still accept trailing arguments" do
    opts = Slopt.new { on :a; on :b= }
    opts.parse %w'-ab foo'
    assert_equal 'foo', opts[:b]
  end

  test "setting/getting the banner" do
    opts = Slopt.new :banner => 'foo'
    assert_equal 'foo', opts.banner

    opts = Slopt.new
    opts.banner 'foo'
    assert_equal 'foo', opts.banner

    opts = Slopt.new
    opts.banner = 'foo'
    assert_equal 'foo', opts.banner
  end

  test "get/[] fetching an options argument value" do
    opts = Slopt.new { on :foo=; on :bar; on :baz }
    opts.parse %w' --foo hello --bar '
    assert_equal 'hello', opts[:foo]
    assert_equal true, opts[:bar]
    assert_nil opts[:baz]
  end

  test "checking for an options presence" do
    opts = Slopt.new { on :foo; on :bar }
    opts.parse %w' --foo '
    assert opts.present?(:foo)
    refute opts.present?(:bar)
  end

  test "ignoring case" do
    opts = Slopt.new { on :foo }
    opts.parse %w' --FOO bar '
    assert_nil opts[:foo]

    opts = Slopt.new(:ignore_case => true) { on :foo= }
    opts.parse %w' --FOO bar '
    assert_equal 'bar', opts[:foo]
  end

  test "supporting dash" do
    opts = Slopt.new { on :foo_bar= }
    opts.parse %w' --foo-bar baz '
    assert_equal 'baz', opts[:foo_bar]
    assert opts.foo_bar?
  end

  test "supporting underscore" do
    opts = Slopt.new { on :foo_bar= }
    opts.parse %w' --foo_bar baz '
    assert_equal 'baz', opts[:foo_bar]
    assert opts.foo_bar?
  end

  # test "parsing an optspec and building options" do
  #   optspec = <<-SPEC
  #   ruby foo.rb [options]
  #   --
  #   v,verbose  enable verbose mode
  #   q,quiet   enable quiet mode
  #   n,name=    set your name
  #   p,pass=?   set your password
  #   SPEC
  #   opts = Slopt.optspec(optspec.gsub(/^\s+/, ''))
  #   opts.parse %w[ --verbose --name Lee ]

  #   assert_equal 'Lee', opts[:name]
  #   assert opts.present?(:verbose)
  #   assert_equal 'enable quiet mode', opts.fetch_option(:quiet).description
  #   assert opts.fetch_option(:pass).accepts_optional_argument?
  # end

  test "ensure negative integers are not processed as options" do
    items = %w(-1)
    Slopt.parse!(items)
    assert_equal %w(-1), items
  end

  test "separators" do
    opts = Slopt.new(:banner => false) do
      on :foo
      separator "hello"
      separator "world"
      on :bar
    end
    assert_equal "        --foo      \nhello\nworld\n        --bar      ", opts.help

    opts = Slopt.new do
      banner "foo"
      separator "bar"
    end
    assert_equal "foo\nbar\n", opts.help
  end

  test "printing help with :help => true" do
    temp_stdout do |string|
      opts = Slopt.new(:help => true, :banner => false)
      assert_raises SystemExit do
        opts.parse %w( --help )
      end
      assert_equal "    -h, --help      Display this help message.\n", string
    end

    temp_stdout do |string|
      opts = Slopt.new(:help => true)
      assert_raises SystemExit do
        opts.parse %w( --help )
      end
      assert_equal "Usage: rake_test_loader [options]\n    -h, --help      Display this help message.\n", string
    end
  end

  test "fallback to substituting - for _ when using <option>?" do
    opts = Slopt.new do
      on 'foo-bar'
    end
    opts.parse %w( --foo-bar )
    assert opts.foo_bar?
  end

  test "option=value syntax does NOT consume following argument" do
    opts = Slopt.new { on :foo=; on 'bar=?' }
    args = %w' --foo=bar baz --bar=zing hello '
    opts.parse!(args)
    assert_equal %w' baz hello ', args
  end

  test "context and return value of constructor block" do
    peep = nil
    ret = Slopt.new { peep = self }
    assert_same ret, peep
    assert !equal?(peep)

    peep = nil
    ret = Slopt.new { |a| peep = self }
    assert !peep.equal?(ret)
    assert_same peep, self

    peep = nil
    ret = Slopt.new { |a, b| peep = self }
    assert_same ret, peep
    assert !equal?(peep)

    peep = nil
    ret = Slopt.new { |a, *rest| peep = self }
    assert_same ret, peep
    assert !equal?(peep)

    peep = nil
    ret = Slopt.parse([]) { peep = self }
    assert_same ret, peep
    assert !equal?(peep)

    peep = nil
    ret = Slopt.parse([]) { |a| peep = self }
    assert !peep.equal?(ret)
    assert_same peep, self

    peep = nil
    ret = Slopt.parse([]) { |a, b| peep = self }
    assert_same ret, peep
    assert !equal?(peep)

    peep = nil
    ret = Slopt.parse([]) { |a, *rest| peep = self }
    assert_same ret, peep
    assert !equal?(peep)
  end

  test "to_s do not break self" do
    slop = Slopt.new do
      banner "foo"
    end

    assert_equal "foo", slop.banner
    slop.to_s
    assert_equal "foo", slop.banner
  end

  test "options with prefixed --no should not default to inverted behaviour unless intended" do
    opts = Slopt.new { on :bar }
    opts.parse %w'--no-bar'
    assert_equal false, opts[:bar]

    opts = Slopt.new { on 'no-bar' }
    opts.parse %w'--no-bar'
    assert_equal true, opts['no-bar']
  end

  test "method missing() is a private method" do
    assert Slopt.new.private_methods.map(&:to_sym).include?(:method_missing)
  end

  test "respond_to?() arity checker is similar of other objects" do
    slop = Slopt.new
    obj = Object.new

    assert_same obj.respond_to?(:__id__), slop.respond_to?(:__id__)
    assert_same obj.respond_to?(:__id__, false), slop.respond_to?(:__id__, false)
    assert_same obj.respond_to?(:__id__, true), slop.respond_to?(:__id__, true)

    assert_raises ArgumentError do
      slop.respond_to? :__id__, false, :INVALID_ARGUMENT
    end
  end

  test "adding a runner" do
    orun = proc { |r| assert_instance_of Slopt, r }
    arun = proc { |r| assert_equal ['foo', 'bar'], r }

    Slopt.parse(%w'foo --foo bar -v bar') do
      on :v
      on :foo=
      run { |o, a| orun[o]; arun[a] }
    end
  end

  test "ensure a runner does not execute when a help option is present" do
    items = []
    Slopt.parse(%w'--help foo bar') do
      run { |o, a| items.concat a }
    end
    assert_equal %w'--help foo bar', items
    items.clear
    temp_stdout do
      assert_raises SystemExit do
        Slopt.parse(%w'--help foo bar', :help => true) do
          run { |o, a| items.concat a }
        end
      end
      assert_empty items
    end
  end

  test "duplicate options should not exist, new options should replace old ones" do
    i = nil
    Slopt.parse(%w'-v') do
      on(:v) { i = 'first' }
      on(:v) { i = 'second' }
    end
    assert_equal 'second', i
  end

  test "taking out the trash" do
    args = []
    opts = Slopt.new { on :f, :foo }
    opts.run { |_, a| args = a }
    opts.parse! %w(--foo bar)
    assert_equal %w(bar), args
    opts.parse! %w(foo)
    assert_equal %w(foo), args
  end

end

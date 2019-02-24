require 'diff-lcs'

require 'test_helper'

TEST_DIR_PATH = File.dirname(__FILE__)

class MarkdownHelperTest < Minitest::Test
  
  TEMPLATES_DIR_NAME = 'templates'
  EXPECTED_DIR_NAME = 'expected'
  ACTUAL_DIR_NAME = 'actual'

  def test_version
    refute_nil MarkdownHelper::VERSION
  end

  def test_link
    [
        ['# Foo', [1, '[Foo](#foo)']],
        ['# Foo Bar', [1, '[Foo Bar](#foo-bar)']],
        ['## Foo Bar', [2, '[Foo Bar](#foo-bar)']],
        ['### Foo Bar', [3, '[Foo Bar](#foo-bar)']],
        ['#### Foo Bar', [4, '[Foo Bar](#foo-bar)']],
        ['##### Foo Bar', [5, '[Foo Bar](#foo-bar)']],
        ['###### Foo Bar', [6, '[Foo Bar](#foo-bar)']],
        [' # Foo Bar', [1, '[Foo Bar](#foo-bar)']],
        ['  # Foo Bar', [1, '[Foo Bar](#foo-bar)']],
        ['   # Foo Bar', [1, '[Foo Bar](#foo-bar)']],
        ['#  Foo', [1, '[Foo](#foo)']],
        ['# Foo#', [1, '[Foo#](#foo)']],
    ].each do |pair|
      text, expected = *pair
      expected_level, expected_link = *expected
      heading = MarkdownHelper::Heading.parse(text)
      assert_equal(expected_level, heading.level)
      assert_equal(expected_link, heading.link)
    end
    [
        '',
        '#',
        '#Foo',
        '####### Foo Bar',
        '    # Foo Bar',
    ].each do |text|
      refute(MarkdownHelper::Heading.parse(text))
    end
  end

  class TestInfo

    attr_accessor \
      :method_under_test,
      :method_name,
      :md_file_basename,
      :md_file_name,
      :test_dir_path,
      :template_file_path,
      :expected_file_path,
      :actual_file_path

    def initialize(method_under_test)
      self.method_under_test = method_under_test
      self.method_name = method_under_test.to_s
      self.md_file_name = "#{md_file_basename}.md"
      self.test_dir_path = File.join(
          TEST_DIR_PATH,
          method_under_test.to_s
      )
      self.template_file_path = File.join(
          test_dir_path,
          TEMPLATES_DIR_NAME,
          md_file_name
      )
      self.expected_file_path = File.join(
          test_dir_path,
          EXPECTED_DIR_NAME,
          md_file_name
      )
      self.actual_file_path = File.join(
          test_dir_path,
          ACTUAL_DIR_NAME,
          md_file_name
      )
    end

    def templates_dir_path
      File.dirname(template_file_path)
    end

    def expected_dir_path
      File.dirname(expected_file_path)
    end

  end

  class IncludeInfo < TestInfo

    attr_accessor \
      :file_stem,
      :file_type,
      :treatment,
      :include_file_path

    def initialize(file_stem, file_type, treatment)
      self.file_stem = file_stem
      self.file_type = file_type
      self.treatment = treatment
      self.md_file_basename = "#{file_stem}_#{treatment}"
      self.include_file_path = "../includes/#{file_stem}.#{file_type}"
      super(:include)
    end

  end

  class CreatePageTocInfo < TestInfo

    def initialize(md_file_basename)
      self.md_file_basename = md_file_basename
      super(:create_page_toc)
    end

  end

  def test_include

    # Create the template for this test.
    def create_template(test_info)
      File.open(test_info.template_file_path, 'w') do |file|
        case
        when test_info.file_stem == :nothing
          file.puts 'This file includes nothing.'
        else
          # Inspect, in case it's a symbol, and remove double quotes after inspection.
          treatment_for_include = test_info.treatment.inspect.gsub('"','')
          include_line = "@[#{treatment_for_include}](#{test_info.include_file_path})"
          file.puts(include_line)
        end
      end
    end

    # Test combinations of treatments and templates.
    {
        :nothing => :txt,
        :md => :md,
        :python => :py,
        :ruby => :rb,
        :text => :txt,
        :text_no_newline => :txt,
        :xml => :xml,
    }.each_pair do |file_stem, file_type|
      [
          :markdown,
          :code_block,
          :comment,
          :pre,
          file_stem.to_s,
      ].each do |treatment|
        test_info = IncludeInfo.new(
            file_stem,
            file_type,
            treatment,
            )
        create_template(test_info)
        common_test(MarkdownHelper.new, test_info)
      end
    end

    # Test automatic page TOC.
    [
        :all_levels,
        :embedded,
        :gappy_levels,
        :mixed_levels,
        :no_headers,
        :no_level_one,
        :includer,
        :nested_headers,
    ].each do |file_stem|
      test_info = IncludeInfo.new(
          file_stem,
          :md,
          :page_toc,
          )
      common_test(MarkdownHelper.new({:pristine => true}), test_info)
    end

    # Test invalid page TOC title.
    test_info = IncludeInfo.new(
        'invalid_title',
        :md,
        :page_toc
    )
    e = assert_raises(MarkdownHelper::InvalidTocTitleError) do
      common_test(MarkdownHelper.new({:pristine => true}), test_info)
    end
    expected_message = 'TOC title must be a valid markdown header, not No hashes'
    assert_equal(expected_message, e.message)

    # Test multiple page TOC.
    test_info = IncludeInfo.new(
        'multiple',
        :md,
        :page_toc,
        )
    e = assert_raises(MarkdownHelper::MultiplePageTocError) do
      common_test(MarkdownHelper.new({:pristine => true}), test_info)
    end
    expected_message = 'Only one page TOC allowed.'
    assert_equal(expected_message, e.message)

    # Test misplaced page TOC.
    test_info = IncludeInfo.new(
        'misplaced',
        :md,
        :page_toc,
        )
    e = assert_raises(MarkdownHelper::MisplacedPageTocError) do
      common_test(MarkdownHelper.new({:pristine => true}), test_info)
    end
    expected_message = 'Page TOC must be in outermost markdown file.'
    assert_equal(expected_message, e.message)

    # Test treatment as comment.
    test_info = IncludeInfo.new(
        file_stem = 'comment',
        file_type = 'txt',
        treatment = :comment,
    )
    create_template(test_info)
    common_test(MarkdownHelper.new, test_info)

    # Test nested includes.
    test_info = IncludeInfo.new(
        file_stem = 'nested',
        file_type = 'md',
        treatment = :markdown,
    )
    create_template(test_info)
    common_test(MarkdownHelper.new, test_info)

    # Test empty file.
    test_info = IncludeInfo.new(
        file_stem = 'empty',
        file_type = 'md',
        treatment = :markdown,
    )
    common_test(MarkdownHelper.new(:pristine => true), test_info)

    # Test option pristine.
    markdown_helper = MarkdownHelper.new
    [ true, false ].each do |pristine|
      markdown_helper.pristine = pristine
      test_info = IncludeInfo.new(
          file_stem = "pristine_#{pristine}",
          file_type = 'md',
          treatment = :markdown,
      )
      create_template(test_info)
      common_test(markdown_helper, test_info)
    end

    # Test unknown option.
    e = assert_raises(MarkdownHelper::OptionError) do
      markdown_helper = MarkdownHelper.new(:foo => true)
    end
    assert_equal('Unknown option: foo', e.message)

    # Test template open failure.
    test_info = IncludeInfo.new(
        file_stem = 'no_such',
        file_type = 'md',
        treatment = :markdown,
    )
    e = assert_raises(MarkdownHelper::UnreadableTemplateError) do
      common_test(MarkdownHelper.new, test_info)
    end
    expected_message = <<EOT
Could not read template file:
C:/Users/Burde/Documents/GitHub/markdown_helper/test/include/templates/no_such_markdown.md
EOT
    assert_equal(expected_message, e.message)

    # Test markdown (output) open failure.
    test_info = IncludeInfo.new(
        file_stem = 'nothing',
        file_type = 'md',
        treatment = :markdown,
    )
    test_info.actual_file_path = File.join(
        File.dirname(test_info.actual_file_path),
        'nonexistent_directory',
        'nosuch.md',
    )
    e = assert_raises(MarkdownHelper::UnwritableMarkdownError) do
      common_test(MarkdownHelper.new, test_info)
    end
    expected_message = <<EOT
Could not write markdown file:
C:/Users/Burde/Documents/GitHub/markdown_helper/test/include/actual/nonexistent_directory/nosuch.md
EOT
    assert_equal(expected_message, e.message)

    # Test circular includes.
    test_info = IncludeInfo.new(
        file_stem = 'circular_0',
        file_type = 'md',
        treatment = :markdown,
    )
    create_template(test_info)
    expected_inclusions = []
    # The outer inclusion.
    template_file_path = File.join(
        TEST_DIR_PATH,
        'include/templates/includer_0_markdown.md'
    )
    cited_includee_file_path = '../includes/circular_0.md'
    inclusion = MarkdownHelper::Inclusion.new(
        template_file_path: template_file_path,
        markdown_file_path: nil,
        )
    expected_inclusions.push(inclusion)
    # The three nested inclusions.
    [
        [0, 1],
        [1, 2],
        [2, 0],
    ].each do |indexes|
      includer_index, includee_index = *indexes
      includer_file_name = "circular_#{includer_index}.md"
      includee_file_name = "circular_#{includee_index}.md"
      includer_file_path = File.join(
          TEST_DIR_PATH,
          "include/templates/../includes/#{includer_file_name}"
      )
      inclusion = MarkdownHelper::Inclusion.new(
          template_file_path: template_file_path,
          markdown_file_path: nil,
          )
      expected_inclusions.push(inclusion)
    end
    e = assert_raises(MarkdownHelper::CircularIncludeError) do
      common_test(MarkdownHelper.new, test_info)
    end
    expected_message = <<EOT
Circular inclusion: test/include/includes/circular_0.md
Inclusion backtrace, innermost first:
Level 3:
  Site: test/include/includes/circular_2.md:1
  Directive: @[:markdown](circular_0.md)
Level 2:
  Site: test/include/includes/circular_1.md:1
  Directive: @[:markdown](circular_2.md)
Level 1:
  Site: test/include/includes/circular_0.md:1
  Directive: @[:markdown](circular_1.md)
Level 0:
  Site: test/include/templates/circular_0_markdown.md:1
  Directive: @[:markdown](../includes/circular_0.md)
EOT
    assert_equal(expected_message, e.message)

    # Test includee not found.
    test_info = IncludeInfo.new(
                               file_stem = 'includer_0',
                               file_type = 'md',
                               treatment = :markdown,
    )
    create_template(test_info)
    expected_inclusions = []
    # The outer inclusion.
    template_file_path = File.join(
        TEST_DIR_PATH,
        'include/templates/includer_0_markdown.md'
    )
    cited_includee_file_path = '../includes/includer_0.md'
    inclusion = MarkdownHelper::Inclusion.new(
                                             template_file_path: template_file_path,
                                             markdown_file_path: nil,
    )
    expected_inclusions.push(inclusion)
    # The three nested inclusions.
    [
        [0, 1],
        [1, 2],
        [2, 3],
    ].each do |indexes|
      includer_index, includee_index = *indexes
      includer_file_name = "includer_#{includer_index}.md"
      includee_file_name = "includer_#{includee_index}.md"
      includer_file_path = File.join(
          TEST_DIR_PATH,
          "include/templates/../includes/#{includer_file_name}"
      )
      inclusion = MarkdownHelper::Inclusion.new(
                                               template_file_path: includer_file_path,
                                               markdown_file_path: nil,
      )
      expected_inclusions.push(inclusion)
    end
    e = assert_raises(MarkdownHelper::UnreadableIncludeeError) do
      common_test(MarkdownHelper.new, test_info)
    end
    expected_message = <<EOT
Could not read includee file: test/include/includes/includer_3.md
Inclusion backtrace, innermost first:
Level 3:
  Site: test/include/includes/includer_2.md:5
  Directive: @[:markdown](includer_3.md)
Level 2:
  Site: test/include/includes/includer_1.md:3
  Directive: @[:markdown](includer_2.md)
Level 1:
  Site: test/include/includes/includer_0.md:1
  Directive: @[:markdown](includer_1.md)
Level 0:
  Site: test/include/templates/includer_0_markdown.md:1
  Directive: @[:markdown](../includes/includer_0.md)
EOT
    assert_equal(expected_message, e.message)
  end

  # Don't call this 'test_interface' (without the leading underscroe),
  # because that would make it an actual executable test method.
  def _test_interface(test_info)
    File.write(test_info.actual_file_path, '') if File.exist?(test_info.actual_file_path)
    yield
    diffs = diff_files(test_info.expected_file_path, test_info.actual_file_path)
    unless diffs.empty?
      puts 'EXPECTED'
      puts File.read(test_info.expected_file_path)
      puts 'ACTUAL'
      puts File.read(test_info.actual_file_path)
      puts 'END'
    end
    assert_empty(diffs, test_info.actual_file_path)
  end

  def common_test(markdown_helper, test_info)

    # API
    _test_interface(test_info) do
      markdown_helper.send(
          test_info.method_under_test,
          test_info.template_file_path,
          test_info.actual_file_path,
          )
    end

    # CLI
    _test_interface(test_info) do
      options = markdown_helper.pristine ? '--pristine' : ''
      File.write(test_info.actual_file_path, '')
      command = "markdown_helper #{test_info.method_under_test} #{options} #{test_info.template_file_path} #{test_info.actual_file_path}"
      system(command)
    end

  end

  def diff_files(expected_file_path, actual_file_path)
    diffs = nil
    File.open(expected_file_path) do |expected_file|
      expected_lines = expected_file.readlines
      File.open(actual_file_path) do |actual_file|
        actual_lines = actual_file.readlines
        diffs = Diff::LCS.diff(expected_lines, actual_lines)
      end
    end
    diffs
  end

end

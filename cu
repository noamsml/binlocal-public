#!/usr/bin/env ruby
# frozen_string_literal: true

# "Checked upload" - run validations before uploading branch to git
# Note: Many of these validations are kinda specific to my current job.
# Keeping this script here because I think the format is a useful framework.

require 'rainbow'

module Plugins
  def self.rubocop
    rubies = Cu.changes.select { |x| x.end_with? '.rb' }
    return true if rubies.empty?

    system("cd #{Cu.gitroot} && bundle exec rubocop -D --auto-correct #{rubies.join(' ')}") && !Cu.has_diff
  end

  def self.typecheck
    system("cd #{Cu.gitroot} && typecheck")
  end

  def self.devlint
    system("cd #{Cu.gitroot} && dev/lint --fix")
  end

  def self.api_services_validate
    protos = Cu.changes.select { |x| x.end_with? '.proto' }
    return true if protos.empty?

    system("cd #{Cu.gitroot} && uppsala/scripts/api-services/validate")
  end

  def self.schema_validate
    schema_protos = Cu.changes.select { |x| x.end_with? '.proto' }
    return true if schema_protos.empty?

    system("cd #{Cu.gitroot} && dev/check-schema-libraries-versioning")
  end

  def self.consolidate_lines
    system("cd #{Cu.gitroot} && filter_lines.py #{Cu.changed_not_deleted.join(' ')}")
    true
  end

  def self.sc_terraform
    tf_folders = Cu.changed_not_deleted
                   .filter { |f| f.end_with?('.tf') }
                   .map { |f| File.dirname(f) }
                   .sort
                   .uniq

    tf_folders.each do |folder|
      system("cd #{folder} && sc terraform fmt")
    end
  end

  def self.run_edited_tests_rb
    test_files = Cu.changed_not_deleted.filter { |path| path.include?('/test/') && path.end_with?('.rb') }
    return true if test_files.empty?

    system("cd #{Cu.gitroot} && pay test #{test_files.join(' ')}")
  end

  def self.gen_packages
    rubies = Cu.changed_not_deleted.filter { |path| path.end_with?('.rb') }
    return true if rubies.empty?

    system("cd #{Cu.gitroot} && scripts/packages/gen-packages")
  end

  def self.module_dir(path)
    return path if File.exist?(File.join(path, 'BUILD')) || File.exist?(File.join(path, 'BUILD.bazel'))

    if path == '.'
      puts 'WARNING: Found dot path module'
      return nil
    end

    module_dir(File.dirname(path))
  end

  def self.check_junit_build(path)
    return nil unless path

    bazel = if File.exist?(File.join(path, 'BUILD'))
              File.read(File.join(path, 'BUILD'))
            else
              File.read(File.join(path, 'BUILD.bazel'))
            end

    path if bazel.include?('junit4_suite_test')
  end

  def self.all_target(path)
    return nil unless path

    path + ':all'
  end

  def self.test_target(path)
    if path.start_with?('src/main')
      test_path = module_dir(path.sub('src/main', 'src/test'))

      return nil if test_path == 'src/test'

      return all_target(check_junit_build(test_path))
    end

    all_target(check_junit_build(path))
  end

  def self.test_edited_modules_java
    test_targets = Cu.changed_not_deleted.filter { |path| path.end_with?('.java') }
                     .map { |path| module_dir(path) }.compact
                     .map { |dir| test_target(dir) }.compact.uniq
                     .map { |dir| dir.sub('uppsala/', '') }

    return true if test_targets.empty?

    system("cd #{Cu.gitroot}/uppsala && bazel test #{test_targets.join(' ')}")
  end

  def self.has_suspicious_untracked
    files = `git ls-files --others --exclude-standard | grep -E "\\.(rb|yaml|js|jsx|ts|tf)$|^BUILD(.bazel)?$"`.strip

    puts files unless files.empty?

    files.empty?
  end

  def self.format_everything_java
    system('./scripts/format_all.sh')
  end

  def self.beautify_js
    javsies = Cu.changes.select { |x| x.end_with? '.js' }
    return true if javsies.empty?

    javsies.each do |javsie|
      puts "Formatting #{javsie}..."
      tmpname = "/tmp/cujavsie-#{Time.now.nsec}.js"
      system("js-beautify -s 2 #{javsie} > #{tmpname} && mv #{tmpname} #{javsie}")
    end
  end
end

def enable(plugin)
  Cu.plugins_enabled[plugin] = true
end

def disable(plugin)
  Cu.plugins_enabled[plugin] = false
end

module Cu
  def self.plugins_enabled
    @plugins_enabled ||= {
      has_suspicious_untracked: true,
      beautify_js: false,
      rubocop: true,
      consolidate_lines: false,
      typecheck: false,
      run_edited_tests_rb: false,
      test_edited_modules_java: false,
      format_everything_java: false,
      sc_terraform: false,
      gen_packages: false
    }
  end

  def self.plugins_slow
    @plugins_slow ||= {
      run_edited_tests_rb: false,
      test_edited_modules_java: false
    }
  end

  def self.plugins_bare
    @plugins_bare ||= {
      has_suspicious_untracked: true
    }
  end

  def self.has_diff
    !`git diff HEAD`.strip.empty?
  end

  def self.changed_not_deleted
    `git diff $(git merge-base main HEAD) --name-status`.split("\n").map(&:split).reject do |y|
      y[0] == 'D'
    end.map do |z|
      if z[0][0] == 'R'
        z[2]
      else
        z[1]
      end
    end
  end

  def self.changes
    @changes ||= changed_not_deleted.reject { |x| x.include? '.-jooq/' }.reject { |x| x.start_with? 'doc/' }
  end

  def self.actually_push
    system('git push -f --set-upstream origin $(branch)')
  end

  def self.branch
    `branch`.strip
  end

  def self.bad(s)
    puts Rainbow(s).bright.red
    exit 1
  end

  def self.gitroot
    @gitroot ||= `git rev-parse --show-toplevel`.strip
  end

  def self.rcfile
    gitroot + '/curc.rb'
  end

  def self.main(fast, bare)
    load rcfile if File.exist?(rcfile)

    bad "Don't push on main" if branch == 'main'

    bad 'Please commit your changes before pushing.' if has_diff

    plugins_enabled.each do |plugin, enabled|
      next unless enabled
      next if fast && plugins_slow[plugin]
      next if bare && !plugins_bare[plugin]

      puts Rainbow("Running #{plugin}").bright.blue
      bad "Plugin failed: #{plugin}" unless Plugins.send(plugin)
    end

    bad 'Plugins have made changes. Please commit or amend accordingly.' if has_diff

    puts Rainbow('Uploading to git').bright.green

    actually_push
  end
end

Cu.main(ARGV.include?('--fast'), ARGV.include?('--bare'))

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
    test_files = Cu.changed_not_deleted.filter { |path| path.include?("/test/")  && path.end_with?(".rb") }
    return true if test_files.empty?
    system("cd #{Cu.gitroot} && pay test #{test_files.join(' ')}")
  end

  def self.module_dir(path)
    if File.exist?(File.join(path, "BUILD")) || File.exist?(File.join(path, "BUILD.bazel"))
      return path
    end

    if path == "."
      puts "WARNING: Found dot path module"
      return nil
    end

    return module_dir(File.dirname(path))
  end

  def self.check_junit_build(path)
    return nil unless path

    bazel = if File.exist?(File.join(path, "BUILD"))
      File.read(File.join(path, "BUILD"))
    else
      File.read(File.join(path, "BUILD.bazel"))
    end

    if bazel.include?("junit4_suite_test")
      path
    else
      nil
    end
  end

  def self.all_target(path)
    return nil unless path

    path + ":all"
  end

  def self.test_target(path)
    if path.start_with?("src/main")
      test_path = module_dir(path.sub("src/main", "src/test"))

      if (test_path == "src/test")
        return nil
      end

      return all_target(check_junit_build(test_path))
    end

    return all_target(check_junit_build(path))
  end

  def self.test_edited_modules_java
    test_targets = Cu.changed_not_deleted.filter { |path| path.end_with?(".java") }
      .map { |path| module_dir(path) }.compact
      .map { |dir| test_target(dir) }.compact.uniq
      .map { |dir| dir.sub("uppsala/", "") }

    return true if test_targets.empty?

    system("cd #{Cu.gitroot}/uppsala && bazel test #{test_targets.join(' ')}")
  end

  def self.has_suspicious_untracked
    files = `git ls-files --others --exclude-standard | grep -E "\\.(rb|yaml|js|jsx|ts|tf)$|^BUILD(.bazel)?$"`.strip

    if !files.empty?
      puts files
    end

    files.empty?
  end

  def self.format_everything_java
    system("./scripts/format_all.sh")
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
      typecheck: true,
      run_edited_tests_rb: true,
      test_edited_modules_java: true,
      format_everything_java: false,
      sc_terraform: true
    }
  end

  def self.plugins_slow
    @plugins_slow ||= {
      run_edited_tests_rb: true,
      test_edited_modules_java: true
    }
  end

  def self.has_diff
    !`git diff HEAD`.strip.empty?
  end

  def self.changed_not_deleted
    `git diff $(git merge-base master HEAD) --name-status`.split("\n").map(&:split).reject do |y|
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

  def self.main(fast)
    load rcfile if File.exist?(rcfile)

    bad "Don't push on master" if branch == 'master'

    bad 'Please commit your changes before pushing.' if has_diff

    plugins_enabled.each do |plugin, enabled|
      next unless enabled
      next if (fast && plugins_slow[plugin])

      puts Rainbow("Running #{plugin}").bright.blue
      bad "Plugin failed: #{plugin}" unless Plugins.send(plugin)
    end

    if has_diff
      bad 'Plugins have made changes. Please commit or amend accordingly.'
    end

    puts Rainbow('Uploading to git').bright.green

    actually_push
  end
end

Cu.main(ARGV.include?('--fast'))

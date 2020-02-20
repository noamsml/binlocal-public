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

    system("bundle exec rubocop -D --auto-correct #{rubies.join(' ')}")
  end

  def self.typecheck
    system("typecheck")
  end

  def self.consolidate_lines
    system("filter_lines.py #{Cu.changed_not_deleted.join(' ')}")
    true
  end

  def self.run_edited_tests
    system("cd #{Cu.gitroot} && pay test #{Cu.changed_not_deleted.filter { |path| path.include?("/test/") }.join(' ')}")
  end

  def self.has_suspicious_untracked
    files = `git ls-files --others --exclude-standard | grep -E "\\.(rb|yaml|js|jsx)$"`.strip

    if !files.empty?
      puts files
    end

    files.empty?
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
      run_edited_tests: true
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
    `git rev-parse --show-toplevel`.strip
  end

  def self.rcfile
    gitroot + '/curc.rb'
  end

  def self.main
    load rcfile if File.exist?(rcfile)

    bad "Don't push on master" if branch == 'master'

    bad 'Please commit your changes before pushing.' if has_diff

    plugins_enabled.each do |plugin, enabled|
      next unless enabled

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

Cu.main

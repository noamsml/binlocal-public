#!/usr/bin/env ruby

# "Checked upload" - run validations before uploading branch to git

require 'rainbow'

module Plugins
  def self.rubocop
    rubies = Cu.changes.select { |x| x.end_with? ".rb" }
    return unless !rubies.empty?
    system("bundle exec rubocop -D --auto-correct #{rubies.join(' ')}")
  end

  def self.consolidate_lines
    system("filter_lines.py #{Cu.changes.join(' ')}")
    true
  end

  def self.run_all_tests
    system("cd #{Cu.gitroot} && RAILS_ENV=test bundle exec rspec")
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
      rubocop: true,
      consolidate_lines: true
    }
  end

  def self.has_diff
    !`git diff HEAD`.strip.empty?
  end

  def self.changes
    @changes ||= `changed-not-deleted`.split.map(&:strip).reject { |x| x.include? '.-jooq/' }
  end

  def self.actually_push
    system("git push -uf")
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
    gitroot + "/curc.rb"
  end

  def self.main
    load rcfile if File.exist?(rcfile)

    if branch == "master"
      bad "Don't push on master"
    end

    if has_diff
      bad "Please commit your changes before pushing."
    end

    plugins_enabled.each do |plugin, enabled|
      next unless enabled
      puts Rainbow("Running #{plugin}").bright.blue
      bad "Plugin failed: #{plugin}" unless Plugins.send(plugin)
    end

    if has_diff
      bad "Plugins have made changes. Please commit or amend accordingly."
    end

    puts Rainbow("Uploading to git").bright.green

    actually_push
  end
end


Cu.main

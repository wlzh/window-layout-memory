#!/usr/bin/env ruby
# Explicit maintenance only. Stop the app before --apply; never infer the destination.
require 'json'
require 'fileutils'
require 'tempfile'
require 'time'

path, profile_id, display_id, mode = ARGV
abort 'Usage: ruby consolidate-telegram.rb FILE PROFILE_ID DISPLAY_ID [--apply]' unless path && profile_id && display_id && [nil, '--apply'].include?(mode)
original = File.binread(path)
db = JSON.parse(original.dup)
profile = db.fetch('profiles').find { |p| p.fetch('id') == profile_id }
abort 'Profile missing or locked' unless profile && !profile['locked']
abort 'Display not in profile' unless profile.fetch('topology').fetch('displays').any? { |d| d.fetch('id') == display_id }
bundle = 'org.telegram.desktop'
records = profile.fetch('windows').select { |w| w.fetch('identity').fetch('bundle') == bundle }
abort 'No Telegram baseline' if records.empty?
abort 'Strong identities present; manual review required' unless records.all? { |w| %w[identifier document].all? { |k| w.fetch('identity').fetch(k, '').empty? } }
selected = records.reverse.find { |w| w.fetch('displayID') == display_id }
abort 'No saved baseline on requested display' unless selected
replacement = Marshal.load(Marshal.dump(selected))
replacement.fetch('identity')['title'] = ''
windows = profile.fetch('windows').reject { |w| w.fetch('identity').fetch('bundle') == bundle }
windows << replacement
puts "Telegram records: #{records.length} -> 1; other windows: #{windows.length - 1}; mode=#{mode || 'dry-run'}"
abort 'File changed while reading' unless File.binread(path) == original
exit if mode != '--apply'
running = IO.popen(['pgrep', '-x', 'WindowLayoutMemory'], &:read)
abort 'Quit WindowLayoutMemory before applying' unless running.empty?
abort 'File changed while reading' unless File.binread(path) == original
backup = "#{path}.before-telegram-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}"
File.open(backup, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(original); f.flush; f.fsync }
profile['windows'] = windows
profile['revision'] = profile.fetch('revision') + 1
profile['updatedAt'] = Time.now.to_f - Time.utc(2001, 1, 1).to_f
Tempfile.create(['.telegram-migration-', '.json'], File.dirname(path)) do |file|
  file.chmod(0600)
  file.write(JSON.generate(db)); file.flush; file.fsync
  abort 'File changed before replacement' unless File.binread(path) == original
  File.rename(file.path, path)
end
puts "APPLIED; backup=#{backup}"

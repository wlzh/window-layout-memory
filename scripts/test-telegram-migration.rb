#!/usr/bin/env ruby
require 'json'
require 'tmpdir'
require 'open3'

script = File.join(__dir__, 'consolidate-telegram.rb')
Dir.mktmpdir('telegram-migration-tests') do |dir|
  path = File.join(dir, 'layouts.json')
  record = {'identity'=>{'bundle'=>'org.telegram.desktop','identifier'=>'','document'=>'','title'=>'聊天 (71)'},'displayID'=>'mi'}
  db = {'profiles'=>[{'id'=>'profile','locked'=>false,'topology'=>{'displays'=>[{'id'=>'mi'}]},'windows'=>[record,record]}]}
  File.write(path, JSON.generate(db))
  original = File.binread(path)
  stdout, _, status = Open3.capture3('ruby', script, path, 'profile', 'mi')
  abort 'dry-run failed or changed data' unless status.success? && stdout.include?('2 -> 1') && File.binread(path) == original
  _, _, status = Open3.capture3('ruby', script, path, 'profile', 'missing')
  abort 'missing display accepted' if status.success?
  record['identity']['identifier'] = 'stable'
  File.write(path, JSON.generate(db))
  _, _, status = Open3.capture3('ruby', script, path, 'profile', 'mi')
  abort 'strong identity silently merged' if status.success?
end
puts 'TELEGRAM_MIGRATION_TESTS passed=3; temporary fixtures only'

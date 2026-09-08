#!/usr/bin/env ruby
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

root = File.expand_path('..', __dir__)
passed = 0
Dir.mktmpdir('wlm-doc-check-') do |dir|
  %w[docs scripts Sources Resources VERSION BUILD_NUMBER RELEASE_CHANNEL README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md LICENSE].each do |name|
    FileUtils.cp_r(File.join(root, name), dir)
  end
  check = lambda do |name, valid, expected|
    out, err, status = Open3.capture3(RbConfig.ruby, File.join(dir, 'scripts/check-docs.rb'))
    raise "#{name}: #{out}#{err}" unless status.success? == valid && (expected.nil? || (out + err).include?(expected))
    passed += 1
  end
  check.call('valid fixture', true, 'errors=0')
  mutations = [
    ['README.md', ->(s) { s + "\n[broken](docs/not-present.md)\n" }, 'missing docs/not-present.md'],
    ['BUILD_NUMBER', ->(_s) { "999\n" }, 'CFBundleVersion'],
    ['Sources/WindowLayoutMemory/Platform.swift', ->(s) { s.sub("?? \"#{File.read(File.join(dir, 'RELEASE_CHANNEL')).strip}\"", '?? "broken"') }, 'fallback differs'],
    ['docs/ABOUT.md', ->(s) { s.gsub('https://869hr.uk', 'https://invalid.example') }, 'missing author/site']
  ]
  mutations.each do |name, mutation, expected|
    path = File.join(dir, name)
    original = File.read(path)
    File.write(path, mutation.call(original))
    check.call(name, false, expected)
    File.write(path, original)
  end
end
puts "DOC_CHECK_TESTS passed=#{passed} failed=0; temporary fixtures only"

#!/usr/bin/env ruby
# Read-only repository documentation checks; no app launch, signing or network.
require 'pathname'
require 'uri'
require 'open3'

root = Pathname.new(__dir__).parent
errors = []
version = root.join('VERSION').read.strip
channel = root.join('RELEASE_CHANNEL').read.strip
build = root.join('BUILD_NUMBER').read.strip
release = "#{version}-#{channel}"
files = Dir.glob(root.join('*.md').to_s) + Dir.glob(root.join('docs/**/*.md').to_s)
links = 0
files.sort.each do |file|
  content = File.read(file).gsub(/^```[^\n]*\n.*?^```\s*$/m, '')
  content.scan(/\[[^\]]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)/).flatten.each do |target|
    next if target =~ /\A(?:[a-z][a-z0-9+.-]*:|#)/i
    path = URI::DEFAULT_PARSER.unescape(target.split(/[?#]/, 2).first)
    resolved = Pathname.new(file).dirname.join(path).cleanpath
    links += 1
    errors << "#{Pathname.new(file).relative_path_from(root)}: missing #{target}" unless resolved.exist?
  end
end
%w[prd design dev plan].each do |name|
  Dir.glob(root.join('docs/prd/v*').to_s).each do |dir|
    errors << "missing #{dir}/#{name}.md" unless File.file?(File.join(dir, "#{name}.md"))
  end
end
{
  'CFBundleShortVersionString' => version,
  'WLMReleaseChannel' => channel,
  'CFBundleVersion' => build
}.each do |key, expected|
  actual, stderr, status = Open3.capture3('/usr/libexec/PlistBuddy', '-c', "Print #{key}", root.join('Resources/Info.plist').to_s)
  errors << "plist #{key}: #{stderr.strip} / #{actual.strip} != #{expected}" unless status.success? && actual.strip == expected
end
platform = root.join('Sources/WindowLayoutMemory/Platform.swift').read
{ 'marketing' => version, 'channel' => channel, 'build' => build }.each do |key, expected|
  line = platform.lines.find { |s| s.include?("static var #{key}:") }
  errors << "AppVersion #{key} fallback differs" unless line && line.include?("?? \"#{expected}\"")
end
%w[README.md docs/STATUS.md docs/ABOUT.md].each do |name|
  text = root.join(name).read
  errors << "#{name}: missing current version #{release}" unless text.include?(release)
end
notes = root.join("docs/releases/v#{release}.md")
errors << "missing release notes #{release}" unless notes.file?
if notes.file?
  errors << 'release notes build differs' unless notes.read.include?("build #{build}")
end
errors << 'CHANGELOG missing Unreleased' unless root.join('CHANGELOG.md').read.include?('## [Unreleased]')
%w[https://x.com/wlzh https://869hr.uk].each do |url|
  %w[README.md docs/ABOUT.md Sources/WindowLayoutMemory/AboutWindow.swift].each do |name|
    errors << "#{name}: missing author/site #{url}" unless root.join(name).read.include?(url)
  end
end
errors.each { |e| warn "FAIL #{e}" }
puts "DOC_CHECK files=#{files.length} local_links=#{links} errors=#{errors.length}; metadata=#{release}/#{build}"
puts 'Scope: local link targets (not anchors/remote reachability), PRD files, selected version and author metadata. Manual semantic review remains required.'
exit(errors.empty? ? 0 : 1)

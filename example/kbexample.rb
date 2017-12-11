#!/usr/bin/ruby
require 'rubygems'
require 'kbremote'

API_KEY = ENV['KB_KEY']
API_SECRET = ENV['KB_SECRET']
api = KbRemote::API.new(key: API_KEY, secret: API_SECRET)

# List configuration profiles with assigned file group contents
puts "Profiles:"
api.profiles.each do |profile|
  puts " ##{profile[:profileID]} #{profile[:name]}, url #{profile[:properties][:kioskUrl]}"
  if profile[:fileGroup]
    fgroup = api.filegroup(profile[:fileGroup][:fileGroupID])
    fgroup.files.each do |e|
      puts "   - #{e[:path]}"
    end
  end
  #puts JSON.pretty_generate(profile)
end

# List device groups
puts "Device Groups:"
api.device_groups.each do |dg|
  puts " ##{dg[:deviceGroupID]}, #{dg[:name]}, profile ##{dg[:profileID]}"
end

# List device groups
puts "Devices"
api.devices.each do |device|
  puts " #{device[:name]} #{device}"
end
#api.patch_device(30640, name: "First tab")

# Create new file group and upload entire directory into it
if Dir.exist?('/tmp/v3')
  g = api.create_filegroup('testing filegroup')
  g.upload_dir("/tmp/v3")
end

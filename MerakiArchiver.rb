#!/usr/bin/ruby

require 'pp'
require 'httparty'
require 'json'
require 'logger'

require_relative 'Camera'

BEGIN {
  puts "MerakiArchiver is starting..."
	if ARGV.size != 1
		puts "usage: ./MerakiArchiver.rb <orgID>"
		exit
  end
}

END {
  puts "\n\nMerakiArchiver is ending..."

}

def readSingleLineFile(file)
	if File.exist?(file)
		File.read(file)
	else
		puts "Could not find file #{file}"
		exit
	end
end

def getCamerasInOrg(orgId, header)
  # run API call to retrieve organization inventory
	# return array of hashes containing info about the cameras in the organization
  url = "https://api.meraki.com/api/v0/organizations/#{orgId.to_s}/inventory"
  regexpExpr = /MV\d{1,3}[Ww]{0,1}/		# this should match any camera model
  output = Array.new
  response = HTTParty.get(url, :headers => header)
	if (response.code != 200) then return nil end		# for a successful API call, we expect to receive an HTTP code 200

  jResponse = JSON.parse(response.body, symbolize_names: true)	# convert response body to JSON for easier parsing
  (0...jResponse.length).each do |i|
    if (jResponse[i][:model].match(regexpExpr))  # MVs do not have 3 numbers in their model yet
      # puts jResponse[i][:model]
      output << jResponse[i]
    end
  end

  return output
end

def getDevice(cameraObj, header)
	# run API call to get more information about the device
	# return hash with device information
	unless cameraObj.class == Camera
		puts "getDevice got a #{cameraObj.class} object, expecting Camera"
		return nil
	end

	url = "https://api.meraki.com/api/v0/networks/#{cameraObj.networkId}/devices/#{cameraObj.serial}"
	response = HTTParty.get(url, :headers => header)
	if (response.code != 200) then return nil end		# for a successful API call, we expect to receive an HTTP code 200

	return JSON.parse(response.body, symbolize_names: true)	# convert response body to JSON for easier parsing
end

def checkCameraReachable(cameraObj)
	# check if camera is reachable on the LAN
	# mark the camera as not reachable locally only if TCP:443 fails
	unless cameraObj.class == Camera
		puts "checkCameraReachable got a #{cameraObj.class} object, expecting Camera"
		return nil
	end


	puts "Attempting to reach #{cameraObj.name} (#{cameraObj.serial}) at #{cameraObj.lanIp}..."
	`ping #{cameraObj.lanIp} -c 2`
	unless $?.success?
		puts "\tFailed PING"
		cameraObj.isLocal = false
	end

	`curl --connect-timeout 2 --silent #{cameraObj.lanIp}:443`		# this should return an empty reply
	if $?.exitstatus == 52
		puts "\tSuccess TCP:443, camera reachable"
		cameraObj.isLocal = true
		return true
	else
		puts "\tFailed TCP:443"
		cameraObj.isLocal = false
		return false
	end
end


# basic variables
merakiAPIKey = readSingleLineFile("apikey")   # key for API calls
orgId = ARGV[0].to_i    # ID of the organization to look cameras in
baseBody = {}
baseHeaders = {"Content-Type" => "application/json",
            "X-Cisco-Meraki-API-Key" => merakiAPIKey}


puts "API Key: #{'*' * 35}" + merakiAPIKey[-6,5]		# show a portion of the API key


# get the list of all the cameras in this organization and store information about them
tmpList = getCamerasInOrg(orgId, baseHeaders)
if tmpList == nil
	puts "Could not retrieve cameras in organization inventory"
elsif tmpList.empty?
	puts "Organization inventory does not have cameras"
	exit
end


# put the cameras in a list of Camera objects
cameraList = Array.new
(0...tmpList.size).each do |i|
	cameraList << Camera.new(tmpList[i][:mac], tmpList[i][:serial], tmpList[i][:networkId], tmpList[i][:model],
														tmpList[i][:claimedAt], tmpList[i][:publicIp], tmpList[i][:name])
end
# pp cameraList


# do device API call to get more information, like their LAN IP
(0...cameraList.size).each do |i|
	output = getDevice(cameraList[i], baseHeaders)
	cameraList[i].lat = output[:lat]
	cameraList[i].lng = output[:lng]
	cameraList[i].address = output[:address]
	cameraList[i].notes = output[:notes]
	cameraList[i].lanIp = output[:lanIp]
	cameraList[i].tags = output[:tags]
	pp cameraList[i]
end
puts "\n\n"


# check if the cameras are reachable locally
# attempt to ping them and open a TCP:443 connection to their LAN IP
camReachable = 0
camUnreachable = 0
(0...cameraList.size).each do |i|
	# do it like this so we can show how many cameras are reachable/unreachable
	if checkCameraReachable(cameraList[i]) then camReachable += 1 else camUnreachable += 1 end
	puts "\n"
end
puts "Cameras reachable locally: #{camReachable}"
puts "Cameras not reachable locally: #{camUnreachable}"

if camReachable == 0	# if no cameras are reachable locally, exit
	puts "I cannot reach any cameras locally :(, exiting..."
	exit
end


# start building the m3u8 url
# example: https://172-20-6-115.ac17c8630111.devices.meraki.direct/hls/high/high51b064413cc623dfd52233715b0a48bc.m3u8

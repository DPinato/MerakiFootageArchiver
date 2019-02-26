#!/usr/bin/ruby
#
# NOTES:
# 	- cameras are only reached locally
# 	- all cameras need to be in the same organization and network
#   - only tested while cameras are connected with a cable, not on the WiFi

require 'pp'
require 'httparty'
require 'json'
require 'logger'
require 'csv'
require 'date'

require_relative 'Camera'
require_relative 'FFmpegWorker'

SUPPORT_720P = ["MV21", "MV71"]		# also, these are the gen 1 models
SUPPORT_1080P = ["MV22", "MV72", "MV12"]		# these are the gen 2 models


BEGIN {
  puts "MerakiArchiver is starting..."
	if ARGV.size < 1
		puts "Usage: ./MerakiArchiver.rb <orgID>"
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

def readNewListFile(file)
	# find "flux.actions.cameras.video_channels.reset" in the file given
	# return the JSON array flux.actions.cameras.video_channels.reset
	if !File.exist?(file) then return false end		# return false if file cannot be found

	tmpStr = File.read(file)
	matchStr = "flux.actions.cameras.video_channels.reset("
	matchStrSize = matchStr.length

	# grab only the JSON portion of the string
	pos1 = tmpStr.index(matchStr)
	pos2 = tmpStr.index(';', pos1)
	outStr = tmpStr[pos1+matchStrSize, pos2-pos1-1-matchStrSize]

	return JSON.parse(outStr, symbolize_names: true)	# convert response body to JSON for easier parsing
end

def getCamerasInOrg(orgId, header)
  # run API call to retrieve organization inventory
	# return array of hashes containing info about the cameras in the organization
  url = "https://api.meraki.com/api/v0/organizations/#{orgId.to_s}/inventory"
  regexpExpr = /MV\d{1,3}[Ww]{0,1}/		# this should match any camera model
  output = Array.new

  jResponse = runAPICall(url, header)
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
	runAPICall(url, header)
end

def getCameraLink(cameraObj, header)
	# run the videoLink API call for cameras, return string with video link
	unless cameraObj.class == Camera
		puts "getCameraLink got a #{cameraObj.class} object, expecting Camera"
		return nil
	end

	url = "https://api.meraki.com/api/v0/networks/#{cameraObj.networkId}/cameras/#{cameraObj.serial}/videoLink"
	runAPICall(url, header)[:url]
end

def runAPICall(url, header)
	# run API call using url and header provided
	# return false if the call failed, nil if nothing was returned or hash with information
	response = HTTParty.get(url, :headers => header)
	if (response.code != 200) then return false end		# for a successful API call, we expect to receive an HTTP code 200

	return JSON.parse(response.body, symbolize_names: true)	# convert response body to JSON for easier parsing
end

def checkCameraReachable(cameraObj)
	# check if camera is reachable on the LAN
	# mark the camera as not reachable locally only if TCP:443 fails
	unless cameraObj.class == Camera
		puts "checkCameraReachable got a #{cameraObj.class} object, expecting Camera"
		return nil
	end


	puts "Attempting to reach #{cameraObj.name} (#{cameraObj.serial}) at #{cameraObj.lanIp} ..."
	# `ping #{cameraObj.lanIp} -c 2`
	# unless $?.success?
	# 	puts "\tFailed PING"
	# 	cameraObj.isReachable = false
	# end

	`curl --connect-timeout 2 --silent #{cameraObj.lanIp}:443`		# this should return an empty reply
	if $?.exitstatus == 52
		puts "\tSuccess TCP:443, camera reachable"
		cameraObj.isReachable = true
		return true
	else
		puts "\tFailed TCP:443"
		cameraObj.isReachable = false
		return false
	end
end

def readCameraKeys(file)
	tmpHash = {}

	if !File.exist?(file) then return false end		# return false if file cannot be found

	CSV.foreach(file) do |row|
  	if (row[0][0] != '#')		# ignore lines starting with '#'
			tmpHash[row[0]] = row[1]
		end
	end
	return tmpHash
end

def writeCameraKeys(file, inValues)
	unless inValues.class == Hash
		puts "writeCameraKeys received unexpected object #{inValues.class}"
		return false
	end

	File.open(file, "w") { |f|
		f << "# serial,key"		# header
		(0...inValues.keys.size).each do |i|
			f << "\n"
			f << inValues.keys[i] << "," << inValues[inValues.keys[i]]
		end
	}
end

def buildM3U8Url(cameraObj)
	# build the URL for the .m3u8 playlist file
	tmpStr = "https://"
	tmpStr += cameraObj.lanIp.gsub('.', '-')
	tmpStr += "."
	tmpStr += cameraObj.mac.gsub(':', '')
	tmpStr += ".devices.meraki.direct/hls/"

	if (SUPPORT_1080P.index(cameraObj.model[0,4]) != nil)
		# camera model is gen 2
		tmpStr += "high/high"
	end

	tmpStr += cameraObj.cameraKey + ".m3u8"
end



# basic variables
merakiAPIKey = readSingleLineFile("apikey")   # key for API calls
cameraKeysFile = "cameraKeys"
newListFile = "new_list"
baseVideoDir = "."	# directory where video files will be stored and folders for the cameras will be created
orgId = ARGV[0].to_i    # ID of the organization to look cameras in
baseBody = {}
baseHeaders = {"Content-Type" => "application/json",
            "X-Cisco-Meraki-API-Key" => merakiAPIKey}



puts "API Key: #{'*' * 35}" + merakiAPIKey[-6,5]		# show a portion of the API key



# get the list of all the cameras in this organization and store information about them
puts "Getting list of cameras in the organization ..."
tmpList = getCamerasInOrg(orgId, baseHeaders)
if tmpList == nil
	puts "Could not retrieve cameras in organization inventory"
elsif tmpList.empty?
	puts "Organization inventory does not have cameras"
	exit
end

# put the cameras in a list of Camera objects
puts "Found #{tmpList.size} cameras in organization #{orgId}"
cameraList = Array.new
(0...tmpList.size).each do |i|
	cameraList << Camera.new(tmpList[i][:mac], tmpList[i][:serial], tmpList[i][:networkId], tmpList[i][:model],
														tmpList[i][:claimedAt], tmpList[i][:publicIp], tmpList[i][:name])
end
# pp cameraList



# do camera API calls to get more information, like their LAN IP and videoLink
puts "Collecting more information about the cameras ..."
(0...cameraList.size).each do |i|
	output = getDevice(cameraList[i], baseHeaders)
	cameraList[i].lat = output[:lat]
	cameraList[i].lng = output[:lng]
	cameraList[i].address = output[:address]
	cameraList[i].notes = output[:notes]
	cameraList[i].lanIp = output[:lanIp]
	cameraList[i].tags = output[:tags]

	cameraList[i].apiVideoLink = getCameraLink(cameraList[i], baseHeaders)
	cameraList[i].node_id = cameraList[i].apiVideoLink[/\d{5,}/]	# node_id is 5+ digits
end
puts "\n\n"



# check if the cameras are reachable locally
# attempt to ping them and open a TCP:443 connection to their LAN IP
puts "Checking if cameras are reachable ..."
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
puts "\n\n"



# process the new_list file and grab the key for the cameras to store in cameraKeys
puts "Processing new_list file ..."
video_channels = readNewListFile(newListFile)

# assign cameraKey to each Camera object, they are the value of m3u8_filename key
if video_channels
	wKeys = {}		# makes it very easy to pass it to writeCameraKeys

	(0...cameraList.size).each do |i|
		(0...video_channels.size).each do |j|
			# TODO: there should not be a situation where a key is not found
			# unless the camera in question is not in the network where new_list was taken
			if video_channels[j][:node_id] == cameraList[i].node_id
				cameraList[i].cameraKey = video_channels[j][:m3u8_filename]
				wKeys[cameraList[i].serial] = cameraList[i].cameraKey
				next
			end
		end
	end

	# write the values obtained to the cameraKeys file, for caching
	pp cameraList
	writeCameraKeys(cameraKeysFile, wKeys)
else
	puts "Could not find new_list file #{newListFile}"
end



# start building the m3u8 url, cameras that do 1080p streams, will have "high" keywords
# https://<camera-IP>.<cameramac>.devices.meraki.direct/hls/<high>/<high><cameraKey>.m3u8
# read <cameraKey> from the file of cameraKeys collected previously
puts "Reading cameraKeys file: #{cameraKeysFile}"
cameraKeys = readCameraKeys(cameraKeysFile)
if (cameraKeys == false)
	puts "Could not read cameraKeys, exiting ..."
	exit
end
pp cameraKeys



# build the URL and set it to the appropriate Camera object
(0...cameraList.size).each do |i|
	cameraList[i].m3u8Url = buildM3U8Url(cameraList[i])
	pp cameraList[i].getVideoUrl
end
puts "\n\n"



# create directories to store video
puts "Creating directories to store video files ..."
unless (Dir.exist?(baseVideoDir))
	Dir.mkdir(baseVideoDir)
end

(0...cameraList.size).each do |i|
	unless cameraList[i].isReachable
		next
	end

	# call the directories something like <camera-name>_<camera_serial>
	# remove any - or spaces from the directory name
	tmpDir = baseVideoDir + "/#{cameraList[i].name.gsub(' ', '_')}_#{cameraList[i].serial.gsub('-', '')}"
	cameraList[i].videoDir = tmpDir
	if (Dir.exist?(tmpDir))
		puts "Directory already exists, #{tmpDir}"
		next
	else
		puts "Creating directory #{tmpDir}"
		Dir.mkdir(tmpDir)
	end
end
puts "\n\n"



# run the ffmpeg process
# ffmpeg -i "<url>" -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 <location.mp4>
ffmpegTest = FFmpegWorker.new(cameraList[0])
ffmpegTest.maxVideoLength = 60
ffmpegTest.videoOverlap = 10
ffmpegTest.run

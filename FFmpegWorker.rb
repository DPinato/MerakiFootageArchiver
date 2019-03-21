require_relative 'MultiLogger'

class FFmpegWorker

	def initialize(camObj, logger)
		@cameraObj = camObj
		@logObj = logger
		@countVideoNum = 0
		@storedVideoList = Array.new
	end

	def genetateFFmpegCmd()
		# the ffmpeg command is going to look something like
		# # ffmpeg -loglevel quiet -i "<url>" -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 <output_file>
		currDateTime = DateTime.now.strftime("%Y%m%dT%H%M%S").to_s		# name each file according to the current DateTime
		outFile = "#{@cameraObj.videoDir}/#{currDateTime}.mp4"
		@storedVideoList[@countVideoNum % @maxVideosPerCamera] = outFile	# this should allow it to auto rollover
		ffmpegCmd = "ffmpeg -loglevel quiet -i \"#{@cameraObj.m3u8Url}\" -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 #{outFile}"
	end

	def run()
		# run the ffmpeg commands in succession
		# TODO: this does not really do any error checking
		# no storage space? cannot spawn process?
		currPid = 0		# PID of current ffmpeg process
		prevPid = 0		# PID of previous ffmpeg process

		@logObj.write("Starting ffmpeg for #{@cameraObj.serial}", "info", true)
		@logObj.write(self.inspect, "debug", false)
		ffmpegCmd = genetateFFmpegCmd()
		currPid = Process.spawn(ffmpegCmd)
		Process.detach(currPid)
		@countVideoNum += 1
		@logObj.write("#{@cameraObj.serial} - ffmpeg(#{currPid}): #{ffmpegCmd}", "debug", false)

		# wait until the second ffmpeg needs to be run
		@logObj.write("#{@cameraObj.serial} - Sleeping #{@maxVideoLength-@videoOverlap}", "info", true)
		sleep @maxVideoLength-@videoOverlap

		loop do
			# check if an older file needs to be deleted
			if @maxVideosPerCamera != 0 && @countVideoNum >= @maxVideosPerCamera
				# delete the oldest video
				begin
					@logObj.write("#{@cameraObj.serial} - deleting #{@storedVideoList[@countVideoNum % @maxVideosPerCamera]}", "info", true)
					File.delete(@storedVideoList[@countVideoNum % @maxVideosPerCamera])
				rescue => e
					@logObj.write("#{@cameraObj.serial} - #{e}", "error", true)
				end
			end

			# start another ffmpeg and keep going
			prevPid = currPid
			ffmpegCmd = genetateFFmpegCmd()
			currPid = Process.spawn(ffmpegCmd)	# we do not care about the exit status, it will be terminated at some point
			Process.detach(currPid)							# detach the process to avoid generating a whole lot of zombie processes
			@countVideoNum += 1
			@logObj.write("#{@cameraObj.serial} - ffmpeg(#{currPid}): #{ffmpegCmd}", "debug", false)

			# wait until the prevPid ffmpeg needs to be interrupted
			@logObj.write("#{@cameraObj.serial} - Sleeping #{@videoOverlap}, videoCount: #{@countVideoNum}", "info", true)
			sleep @videoOverlap
			Process.kill("INT", prevPid)
			@logObj.write("#{@cameraObj.serial} - killing ffmpeg(#{prevPid})", "debug", false)

			# wait until another ffmpeg needs to be started
			@logObj.write("#{@cameraObj.serial} - Sleeping #{@maxVideoLength-(@videoOverlap*2)}", "info", true)
			sleep @maxVideoLength-(@videoOverlap*2)

		end
	end


	attr_accessor :cameraObj	# reference to Camera object this ffmpeg worker works for
	attr_accessor :logObj			# reference to @logObj object
	attr_accessor :maxVideoLength		# maximum length of .mp4 output video files, in seconds
	attr_accessor :videoOverlap			# when before the end of a file, a second ffmpeg is started
	attr_accessor :maxVideosPerCamera		# max number of videos that will be stored at a given time for
																			# this camera. If this value is reached, the oldest videos will
																			# begin to be deleted
																			# if this is 0, store unlimited video files

	attr_accessor :countVideoNum		# count how many videos have been stored for this camera
	attr_accessor :storedVideoList	# list of videos stored, by file name
end

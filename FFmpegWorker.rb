require_relative 'MultiLogger'

class FFmpegWorker

	def initialize(camObj, logger)
		@cameraObj = camObj
		@logObj = logger
	end

	def genetateFFmpegCmd()
		# the ffmpeg command is going to look something like
		# # ffmpeg -loglevel quiet -i "<url>" -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 <output_file>
		currDateTime = DateTime.now.strftime("%Y%m%dT%H%M%S").to_s		# name each file according to the current DateTime
		outFile = "#{@cameraObj.videoDir}/#{currDateTime}.mp4"
		ffmpegCmd = "ffmpeg -loglevel quiet -i \"#{@cameraObj.m3u8Url}\" -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 #{outFile}"
	end

	def run()
		# run the ffmpeg commands in succession
		currPid = 0		# PID of current ffmpeg process
		prevPid = 0		# PID of previous ffmpeg process

		@logObj.write("Starting ffmpeg for #{@cameraObj.serial}", "info", true)
		ffmpegCmd = genetateFFmpegCmd()
		currPid = Process.spawn(ffmpegCmd)
		@logObj.write("#{@cameraObj.serial} - ffmpeg(#{currPid}): #{ffmpegCmd}", "debug", false)

		# wait until the second ffmpeg needs to be ran
		@logObj.write("#{@cameraObj.serial} - Sleeping #{@maxVideoLength-@videoOverlap}", "info", true)
		sleep @maxVideoLength-@videoOverlap

		loop do
			# start another ffmpeg
			prevPid = currPid
			ffmpegCmd = genetateFFmpegCmd()
			currPid = Process.spawn(ffmpegCmd)
			@logObj.write("#{@cameraObj.serial} - ffmpeg(#{currPid}): #{ffmpegCmd}", "debug", false)

			# wait until the prevPid ffmpeg needs to be interrupted
			@logObj.write("#{@cameraObj.serial} - Sleeping #{@videoOverlap}", "info", true)
			sleep @videoOverlap
			Process.kill("INT", prevPid)
			@logObj.write("#{@cameraObj.serial} - killing ffmpeg(#{prevPid})", "debug", false)


			# wait until another ffmpeg needs to be started
			@logObj.write("#{@cameraObj.serial} - Sleeping #{@maxVideoLength-(@videoOverlap*2)}", "info", true)
			puts "#{@cameraObj.serial} - Sleeping #{@maxVideoLength-(@videoOverlap*2)}"
			sleep @maxVideoLength-(@videoOverlap*2)

		end
	end


	attr_accessor :cameraObj	# reference to Camera object this ffmpeg worker works for
	attr_accessor :logObj			# reference to @logObj object
	attr_accessor :maxVideoLength		# maximum length of .mp4 output video files, in seconds
	attr_accessor :videoOverlap			# when before the end of a file, a second ffmpeg is started

end

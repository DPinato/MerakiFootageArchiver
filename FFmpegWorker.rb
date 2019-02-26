
class FFmpegWorker

	def initialize(camObj)
		@cameraObj = camObj
	end

	def genetateFFmpegCmd()
		currDateTime = DateTime.now.strftime("%Y%m%dT%H%M%S").to_s		# name each file according to the current DateTime
		outFile = "#{@cameraObj.videoDir}/#{currDateTime}.mp4"
		ffmpegCmd = "ffmpeg -loglevel quiet -i \"#{@cameraObj.getVideoUrl}\" -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 #{outFile}"
	end

	def run()
		# run the ffmpeg commands in succession
		currPid = 0		# PID of current ffmpeg process
		prevPid = 0		# PID of previous ffmpeg process

		puts "Starting ffmpeg for #{@cameraObj.serial}"
		ffmpegCmd = genetateFFmpegCmd()
		currPid = Process.spawn(ffmpegCmd)

		# wait until the second ffmpeg needs to be ran
		puts "Sleeping #{@maxVideoLength-@videoOverlap}"
		sleep @maxVideoLength-@videoOverlap

		loop do
			# start another ffmpeg
			prevPid = currPid
			ffmpegCmd = genetateFFmpegCmd()
			currPid = Process.spawn(ffmpegCmd)

			# wait until the prevPid ffmpeg needs to be interrupted
			puts "Sleeping #{@videoOverlap}"
			sleep @videoOverlap
			Process.kill("INT", prevPid)


			# wait until another ffmpeg needs to be started
			puts "Sleeping #{@maxVideoLength-(@videoOverlap*2)}"
			sleep @maxVideoLength-(@videoOverlap*2)

		end
	end


	attr_accessor :cameraObj	# reference to camera object
	attr_accessor :maxVideoLength		# maximum length of .mp4 output video files, in seconds
	attr_accessor :videoOverlap			# when before the end of a file, a second ffmpeg is started

end

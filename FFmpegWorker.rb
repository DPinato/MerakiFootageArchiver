# Here I am starting the ffmpeg process in background with &, not with Process.spawn because it looks like
# whenever I kill it even after detatching it, it does not want to go away until the ruby process ends
# Below, are the results of my tests:
#
# - Process.spawn, while ruby process is still running
# root       468  0.0  0.5  10208  5096 ?        Ss   Mar16   0:00 /usr/sbin/sshd -D
# root     15820  0.0  0.6  11528  5748 ?        Ss   20:14   0:00  \_ sshd: pi [priv]
# pi       15829  0.0  0.3  11528  3520 ?        S    20:14   0:00  |   \_ sshd: pi@pts/0
# pi       15832  0.0  0.4   6160  4216 pts/0    Ss   20:14   0:00  |       \_ -bash
# pi       15980 14.2  0.7  19516  7436 pts/0    Sl+  20:29   0:00  |           \_ /usr/bin/ruby ./Process.rb 10
# pi       15982  0.0  0.0   1900   428 pts/0    S+   20:29   0:00  |               \_ sh -c ping -c 1000 google.com > pi
# pi       15983  0.0  0.2   5216  2028 pts/0    S+   20:29   0:00  |                   \_ ping -c 1000 google.com
#
#
# - Process.spawn, after ruby process finishes running
# pi       15982  0.0  0.0   1900   428 pts/0    S    20:29   0:00 sh -c ping -c 1000 google.com > ping.log
# pi       15983  0.0  0.2   5216  2028 pts/0    S    20:29   0:00  \_ ping -c 1000 google.com



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
		# ffmpeg -loglevel -nostdin quiet -i <url> -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 <output_file>
		currDateTime = DateTime.now.strftime("%Y%m%dT%H%M%S").to_s		# name each file according to the current DateTime
		outFile = "#{@cameraObj.videoDir}/#{currDateTime}.mp4"
		@storedVideoList[@countVideoNum % @maxVideosPerCamera] = outFile	# this should allow it to auto rollover
		ffmpegCmd = "ffmpeg -loglevel quiet -nostdin -i #{@cameraObj.m3u8Url} -bsf:a aac_adtstoasc -vcodec copy -c copy -crf 50 #{outFile} &"
	end

	def getCmdPid(str)
		# use ps and grep to get the PID of a process that is running in the background
		# using the sys-proctable gem makes it more platform-agnostic, i.e. it should work in Mac OS too
		s = Sys::ProcTable.ps
		s.each do |p|
			if p.name == "ffmpeg" && p.cmdline == str[0...-2]
				return p.pid
			end
		end
		return nil
	end

	def run()
		# run the ffmpeg commands in succession
		# TODO: this does not really do any error checking
		# no storage space? cannot start/kill ffmpeg process?
		currPid = 0		# PID of current ffmpeg process
		prevPid = 0		# PID of previous ffmpeg process

		@logObj.write("Starting ffmpeg for #{@cameraObj.serial}", "info", true)
		@logObj.write(self.inspect, "debug", false)
		ffmpegCmd = genetateFFmpegCmd()
		system(ffmpegCmd)		# running the command with `` does not do the job, as those are a blocking operation
		currPid = getCmdPid(ffmpegCmd)
		@logObj.write("#{@cameraObj.serial} - ffmpeg(#{currPid}): #{ffmpegCmd}", "debug", true)
		@countVideoNum += 1

		# wait until the second ffmpeg needs to be run
		@logObj.write("#{@cameraObj.serial} - Sleeping #{@maxVideoLength-@videoOverlap}", "info", true)
		sleep @maxVideoLength-@videoOverlap


		loop do
			# check if an older file needs to be deleted
			if @maxVideosPerCamera != 0 && @countVideoNum >= @maxVideosPerCamera-1
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
			system(ffmpegCmd)
			currPid = getCmdPid(ffmpegCmd)
			@countVideoNum += 1
			@logObj.write("#{@cameraObj.serial} - ffmpeg(#{currPid}): #{ffmpegCmd}", "debug", true)


			# wait until the prevPid ffmpeg needs to be interrupted
			@logObj.write("#{@cameraObj.serial} - Sleeping #{@videoOverlap}, videoCount: #{@countVideoNum}", "info", true)
			sleep @videoOverlap
			`kill -15 #{prevPid}`	# leave this as blocking, as this kill is pretty important
			@logObj.write("#{@cameraObj.serial} - killed ffmpeg(#{prevPid})", "debug", true)

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

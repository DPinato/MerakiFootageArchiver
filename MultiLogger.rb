# this class, used in conjunction with Logger, allows logging to both STDOUT
# and log files
# got idea from: https://stackoverflow.com/questions/6407141/how-can-i-have-ruby-logger-log-output-to-stdout-as-well-as-file

class MultiLogger
  def initialize(logger)
     @logObj = logger
  end

  def write(msg, severity, toStdout)
		# toStdout is a boolean indicating whether the message will be writen to STDOUT
		case severity
		when "debug"
			loggerDebug(msg)
		when "error"
			loggerError(msg)
		when "fatal"
			loggerFatal(msg)
		when "info"
			loggerInfo(msg)
		end

		if (toStdout)
			puts msg
		end

  end

	def loggerDebug(msg)
		@logObj.debug(msg)
	end

	def loggerError(msg)
		@logObj.error(msg)
	end

	def loggerFatal(msg)
		@logObj.fatal(msg)
	end

	def loggerInfo(msg)
		@logObj.info(msg)
	end

  def close
    @logObj.close
  end

	attr_accessor :logObj
end

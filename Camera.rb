

class Camera

	def initialize(mac, serial, networkId, model, claimedAt, publicIP, name)
		# this should only get called after the parameters from the organization inventory API call are retrieved
		@mac, @serial, @networkId, @model, @claimedAt, @publicIP, @name = mac, serial, networkId, model, claimedAt, publicIP, name
	end



  attr_accessor :mac, :serial, :networkId, :model, :claimedAt, :publicIp, :name   # from the invetory API call
  attr_accessor :lat, :lng, :address, :notes, :lanIp, :tags		# from the devices API call

	attr_accessor :isLocal	# indicates whether the camera is accessible locally
	attr_accessor :m3u8Url
end

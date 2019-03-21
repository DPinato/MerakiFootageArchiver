## DISCLAIMER
- This project was not built by Cisco Meraki and it is not in any way affiliated with Cisco Meraki
- I have done my best to test this code as much as possible, however use at your own risk


## What is this?
This is effectively an ffmpeg wrapper, allowing to store locally video from Cisco Meraki MV cameras in an mp4 format. Cisco Meraki MV cameras use [HTTP Live Streaming (HLS)](https://en.wikipedia.org/wiki/HTTP_Live_Streaming) technology to store and playback video in a web browser.


## How does this work?
- Details about the LAN IP addresses of the cameras are retrieved using the Cisco Meraki API.
-
- A separate directory is created for each camera. The length of each video file can be configured as well as how long before the end of the previous recording, the next recording will start, to avoid the chance of not capturing video for a period of time.


## Limitations
- All the cameras being monitored have to be within the same dashboard organization


## Examples

./MerakiArchiver.rb \<orgID\>

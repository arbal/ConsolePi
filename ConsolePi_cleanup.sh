#!/bin/sh
#
### BEGIN INIT INFO
# Provides:          
# Required-Start:
# Required-Stop:     
# Should-Start: 
# Should-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Clean out temp files used by ConsolePi puship function
# Description:  Clean up temp files used by ConsolePi on boot or halt.  Gracefully shutdown OpenVPN on shutdown
### END INIT INFO

case "$1" in
start|stop)
  for i in eth0 wlan0 tun0 tun1 tun2 tun3 tun4 tun5; do
    i="/tmp/$i"
    [ -e $i ] && rm $i 
  done
  echo puship-ConsolePiCleanUp CleanUp Complete
  exit 0
  ;;
stop)
  pkill -SIGTERM -e -F /var/run/ovpn.pid
  echo puship OpenVPN Gracefully shutdown by ConsolePiCleanUp
  exit 0
  ;; 
esac
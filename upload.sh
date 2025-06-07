#!/bin/zsh

set -x

host='192.168.0.8'
[ -n "$1" ] && host="$1"

# libswift.dylib

curl -s4k "http://$host/delete" \
'-dpath=/Documents/dylib/GCDWebServer.dylib'

curl -s4k "http://$host/upload" \
-F 'path=/Documents/dylib/' \
-F 'files[]=@/Volumes/RamDisk/GCDWebServer.dylib'

curl -s4k "http://$host/list?path=/Documents/dylib/" | jt

exit


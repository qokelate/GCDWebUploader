#!/bin/zsh

# set -ex

plist="$1"
[ ! -f "$plist" ] && exit

bonjour=`'/usr/libexec/PlistBuddy' -c "print ':NSBonjourServices'" "${plist}"`

'/usr/libexec/PlistBuddy' -x -c "delete ':NSBonjourServices'" "${plist}" || true
'/usr/libexec/PlistBuddy' -x -c "add ':NSBonjourServices' array" "${plist}" || true

echo "$bonjour" | while read line; do
    # echo "$line"
    [ '_lnp._tcp.' = "$line" ] && continue
    [ '_http._tcp' = "$line" ] && continue
    [ '_bonjour._tcp' = "$line" ] && continue
    [ '_' = "${line:0:1}" ] && \
    '/usr/libexec/PlistBuddy' -x -c "add ':NSBonjourServices:0' string '$line'" "${plist}"
done


'/usr/libexec/PlistBuddy' -x -c "add ':NSBonjourServices:0' string '_bonjour._tcp'" "${plist}"
'/usr/libexec/PlistBuddy' -x -c "add ':NSBonjourServices:0' string '_lnp._tcp.'" "${plist}"
'/usr/libexec/PlistBuddy' -x -c "add ':NSBonjourServices:0' string '_http._tcp'" "${plist}"

exit

'/usr/libexec/PlistBuddy' -x -c "delete ':NSAppTransportSecurity' dict" "${plist}" || true
'/usr/libexec/PlistBuddy' -x -c "add ':NSAppTransportSecurity' dict" "${plist}"
'/usr/libexec/PlistBuddy' -x -c "add ':NSAppTransportSecurity:NSAllowsArbitraryLoads' bool 'true'" "${plist}"



'/usr/libexec/PlistBuddy' -x -c "add ':NSLocalNetworkUsageDescription' string 'Privacy - Local Network Usage Description'" "${plist}" || true
'/usr/libexec/PlistBuddy' -x -c "add ':UIFileSharingEnabled' bool 'true'" "${plist}" || true

exit

<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>

<key>NSBonjourServices</key>
<array>
    <string>_bonjour._tcp</string>
    <string>_lnp._tcp.</string>
    <string>_http._tcp</string>
</array>

<key>NSLocalNetworkUsageDescription</key>
<string>Privacy - Local Network Usage Description</string>

<key>UIFileSharingEnabled</key>
<true/>

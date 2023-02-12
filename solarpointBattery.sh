#!/usr/bin/env bash

# This script will retrieve battery information from a SunMax SolarPoint device in JSON format
#
# With thanks to @pfanntec in the UI community who got the JSON RPC access rolling
#
set -uo pipefail

usage() {
	echo "Usage ${0}  -u userName -p password [-v] targetDevice"
	echo "-u user name for Solarpoint device"
	echo "-p password for Solarpoint device"
	echo "-h help"
	exit 2
}

declare TARGET
declare PASSWORD
declare VERBOSE=
declare USERNAME

while getopts 'u:p:vh' OPT
do
  case "$OPT" in
    u) USERNAME=${OPTARG} ;;
    p) PASSWORD=${OPTARG} ;;
    v) VERBOSE=true ;;
    *) usage ;;    
  esac
done

shift $((OPTIND-1))
TARGET=$*

if [ -z "${TARGET:-}" ]; then
    echo "Missing Target device"
	usage;
fi

if [ -z "${USERNAME:-}" ]; then
    echo "Missing user name"
	usage;
fi

if [ -z "${PASSWORD:-}" ]; then
    echo "Missing password"
	usage;
fi

if [[ -n "${VERBOSE}" ]]; then set -x; fi
	
SessionJSON=$(curl -s "https://$TARGET/ubus"\
 	--insecure \
 	-H "Content-Type: application/json" \
	-H "Accept: application/json"\
	--data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"00000000000000000000000000000000\",\"session\",\"login\",{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"timeout\":30}]}")
	

if [[ -n "${VERBOSE}" ]]; then echo "${SessionJSON}"; fi	
	         	 
SESSION_ID=$(echo "${SessionJSON}" | jq ".result[1].ubus_rpc_session")

if [[ -n "${VERBOSE}" ]]; then echo SessionID="${SESSION_ID}"; fi

if [[ -z "${SESSION_ID}" ]]; then echo "Could not retrieve Session ID: ${SessionJSON}";
else
	BatteryData=$(curl -s "https://$TARGET/ubus"\
		--insecure\
		-H "Content-Type: application/json"\
		-H "Accept: application/json"\
		--data "{\"jsonrpc\":\"2.0\",\"id\":344,\"method\":\"call\",\"params\":[$SESSION_ID,\"battery\",\"stats\",{\"timeout\":30}]}")
	echo "${BatteryData}"
fi




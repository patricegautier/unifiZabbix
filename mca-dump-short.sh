#!/bin/bash
# set -x

usage()
{
	echo "Usage "${0}"  -i privateKeyPath -u user -d targetDevice [-t AP|SWITCH|UDMP|USG|CK]"
	echo "-i specify private public key pair"
	echo "-u SSH user name for Unifi device"
	echo "-d IP or FQDN for Unifi device"
	echo "-d Unifi device type"
	exit 2
}


while getopts 'i:u:t:hd:v' OPT
do
  case $OPT in
    i) PRIVKEY_PATH=${OPTARG} ;;
    u) USER=${OPTARG} ;;
    t) DEVICE_TYPE=${OPTARG} ;;
    d) TARGET_DEVICE=${OPTARG} ;;
    v) VERBOSE=true ;;
    h) usage ;;
  esac
done

if [[ ${DEVICE_TYPE} == 'AP' ]]; then
	JQ_OPTIONS='del (.port_table) | del(.radio_table[].scan_table) | del (.vap_table[].sta_table)'
elif [[ ${DEVICE_TYPE} == 'SWITCH' ]]; then
	JQ_OPTIONS='del (.port_table[].mac_table)'
elif [[ ${DEVICE_TYPE} == 'UDMP' ]]; then
	JQ_OPTIONS='del (.dpi_stats) | del(.fingerprints)'
elif [[ ${DEVICE_TYPE} == 'USG' ]]; then
	JQ_OPTIONS='del (.dpi_stats) | del(.fingerprints)'
elif [[ ${DEVICE_TYPE} == 'CK' ]]; then
	JQ_OPTIONS= 
else
	echo "Unknown device Type: "${DEVICE_TYPE}
	usage
fi
	


if ! [[ -z ${VERBOSE} ]]; then
    echo 'ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new -i ${PRIVKEY_PATH} ${USER}@${TARGET_DEVICE} mca-dump | jq --indent 0 "${JQ_OPTIONS}"'
fi



ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new -i ${PRIVKEY_PATH} ${USER}@${TARGET_DEVICE} mca-dump | jq --indent 0 "${JQ_OPTIONS}"





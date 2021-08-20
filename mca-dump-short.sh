#!/bin/bash
# set -x

usage()
{
	cat << EOF
Usage ${0}  -i privateKeyPath -u user -v -d targetDevice [-t AP|SWITCH|SWITCH_FEATURE_DISCOVERY|UDMP|USG|CK]
	-i specify private public key pair
	-u SSH user name for Unifi device
	-d IP or FQDN for Unifi device
	-t Unifi device type
	-v verbose and non compressed output
EOF
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
elif [[ ${DEVICE_TYPE} == 'SWITCH_FEATURE_DISCOVERY' ]]; then
        JQ_OPTIONS='[ .port_table | { power:   any (  .poe_power >= 0 ) , total_power_consumed_key_name: "total_power_consumed", max_power_key_name: "max_power" }    ]'
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
	


INDENT_OPTION="--indent 0"


if ! [[ -z ${VERBOSE} ]]; then
	INDENT_OPTION=
    	echo 'ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new -i '${PRIVKEY_PATH} ${USER}@${TARGET_DEVICE}' "mca-dump | gzip" | gunzip | jq '${INDENT_OPTION} ${JQ_OPTIONS}
fi



ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new -i ${PRIVKEY_PATH} ${USER}@${TARGET_DEVICE} "mca-dump | gzip" | gunzip | jq ${INDENT_OPTION} "${JQ_OPTIONS}"





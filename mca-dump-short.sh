#!/bin/bash
# set -x

usage()
{
	cat << EOF
Usage ${0}  -i privateKeyPath -p <passwordFilePath> -u user -v -d targetDevice [-t AP|SWITCH|SWITCH_FEATURE_DISCOVERY|UDMP|USG|CK]
	-i specify private public key pair path
	-p specify password file path to be passed to sshpass -f. Note if both -i and -p are provided, the password file will be used
	-u SSH user name for Unifi device
	-d IP or FQDN for Unifi device
	-t Unifi device type
	-v verbose and non compressed output
EOF
	exit 2
}

SSHPASS_OPTIONS=
PRIVKEY_OPTION=
PASSWORD_FILE_PATH=
VERBOSE_OPTION=


while getopts 'i:u:t:hd:vp:' OPT
do
  case $OPT in
    i) PRIVKEY_OPTION="-i "${OPTARG} ;;
    u) USER=${OPTARG} ;;
    t) DEVICE_TYPE=${OPTARG} ;;
    d) TARGET_DEVICE=${OPTARG} ;;
    v) VERBOSE=true ;;
    p) PASSWORD_FILE_PATH=${OPTARG} ;;
    h) usage ;;
  esac
done

if ! [[ -z ${VERBOSE} ]]; then
        VERBOSE_OPTION="-v"
fi

# {$UNIFI_SSHPASS_PASSWORD_PATH} means the macro didn't resolve in Zabbix
if ! [[ -z ${PASSWORD_FILE_PATH} ]] && ! [[ ${PASSWORD_FILE_PATH} == "{\$UNIFI_SSHPASS_PASSWORD_PATH}" ]]; then 
	SSHPASS_OPTIONS="-f "${PASSWORD_FILE_PATH}" "${VERBOSE_OPTION}
	PRIVKEY_OPTION=
fi


if [[ ${DEVICE_TYPE} == 'AP' ]]; then
	JQ_OPTIONS='del (.port_table) | del(.radio_table[].scan_table) | del (.vap_table[].sta_table)'
elif [[ ${DEVICE_TYPE} == 'SWITCH' ]]; then
	JQ_OPTIONS='del (.port_table[].mac_table)'
elif [[ ${DEVICE_TYPE} == 'SWITCH_FEATURE_DISCOVERY' ]]; then
        JQ_OPTIONS="[ { power:  .port_table |  any (  .poe_power >= 0 ) ,\
	total_power_consumed_key_name: \"total_power_consumed\",\
	max_power_key_name: \"max_power\",\
	max_power: .total_max_power,\
	percent_power_consumed_key_name: \"percent_power_consumed\",\
	has_eth1: .has_eth1,\
	has_temperature: .has_temperature,\
	temperature_key_name: \"temperature\",\
        overheating_key_name: \"overheating\",\
	} ]"
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
    	echo ${SSHPASS_COMMAND} 'ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new '${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE}' "mca-dump | gzip" | gunzip | jq '${INDENT_OPTION} ${JQ_OPTIONS}
fi


if ! [[ -z ${SSHPASS_OPTIONS} ]]; then
	sshpass ${SSHPASS_OPTIONS} ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE} "mca-dump | gzip" | gunzip | jq ${INDENT_OPTION} "${JQ_OPTIONS}"
else
	ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE} "mca-dump | gzip" | gunzip | jq ${INDENT_OPTION} "${JQ_OPTIONS}"
fi




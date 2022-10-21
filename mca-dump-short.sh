#!/bin/bash
#set -xv
set -uo pipefail

declare HE_RSA_SSH_KEY_OPTIONS='-o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa'

#AP|SWITCH|SWITCH_FEATURE_DISCOVERY|SWITCH_DISCOVERY|UDMP|USG|CK
declare -A VALIDATOR_BY_TYPE
VALIDATOR_BY_TYPE["AP"]=".vap_table? != null and .radio_table != null and ( .radio_table | map(select(.athstats!=null)) | length>0 ) "
VALIDATOR_BY_TYPE["UDMP"]=".network_table? != null"
VALIDATOR_BY_TYPE["USG"]="( .network_table? != null ) and ( .network_table | map(select(.mac!=null)) | length>0 ) and ( ( .[\"system-stats\"].temps | length ) == 4 ) "



# thanks @zpolisensky for this contribution
#shellcheck disable=SC2016
PORT_NAMES_AWK='
BEGIN { IFS=" \n"; first=1; countedPortId=0 }
match($0, "^interface 0/[0-9]+$") { 
	portId=substr($2,3)
}
match($0, "^interface [A-z0-9]+$") { 
	countedPortId=countedPortId+1
	portId=countedPortId
}
/description / {
		desc=""
		defaultDesc="Port " portId
		for (i=2; i<=NF; i++) {
			f=$i
			if (i==2) f=substr(f,2)
			if (i==NF) 
				f=substr(f,1,length(f)-1)
			else
				f=f " "
			desc=desc f
		}
		if (first != 1) printf "| "
		first=0
		if ( desc == defaultDesc) 
			desc="-"
		else
			desc="(" desc ")"
		printf ".port_table[" portId-1 "] += { \"port_desc\": \"" desc "\" }"
	}'



# for i in 51 52 53 54 55 56 58; do  echo "-------- 192.168.217.$i"; time mca-dump-short.sh -t SWITCH_DISCOVERY -u patrice -d 192.168.217.$i  | jq | grep -E "model|port_desc"; done
# for i in 50 51 52 53 54 56 59; do  echo "-------- 192.168.207.$i"; time mca-dump-short.sh -t SWITCH_DISCOVERY -u patrice -d 192.168.207.$i  | jq | grep -E "model|port_desc"; done

declare SLEEP_INTERVAL=0.5
declare TIMEOUT_MULTIPLIER=2   #  1/SLEEP_INTERVAL

runWithTimeout() {
    local timeout=$(( $1 * TIMEOUT_MULTIPLIER ))
    if [[ -n "${timeout}" ]]; then
		shift 
	
		( "$@" &
		  local child=$!
		  # Avoid default notification in non-interactive shell for SIGTERM
		  trap -- "" SIGTERM
			( 	
				#echo "Starting Watchdog with ${timeout}s time out"
				local elapsedCount=0
				local childGone=
				while (( elapsedCount < timeout )) && [[ -z "${childGone}" ]]; do
					sleep $SLEEP_INTERVAL
					elapsedCount=$(( elapsedCount + 1 ))
					#echo "Waiting for child #${child}:  Elapsed $elapsedCount"
					local childPresent; 
					#shellcheck disable=SC2009
					childPresent=$(ps -o pid -p ${child} | grep -v PID)
					if [[ -z "${childPresent}" ]]; then
						# the child has either completed or died, either way no time out
						childGone=true
						#echo "Child #${child} left"
					fi
				done
				if [[ -z "${childGone}" ]]; then #it's a timeout
					#echo "Child #${child} timed out"				
					kill -KILL $child
					#local killResult=$?
					#if (( killResult != 0 )); then
						#echo "Could not kill child still running, pid $child"
					#fi
				fi
				#echo Exiting Watchdog
			) &
		  wait $child 2>/dev/null
		  exit $?
		)
	else
		"$@"
	fi
}

function errorJsonWithReason() {
	local reason; reason=$(echo "$1" | tr -d "\"'\n\r" )
	echo '{ "mcaDumpError":"Error", "reason":"'"${reason}"'", "device":"'"${TARGET_DEVICE}"'" }'
}

function retrievePortNamesInto() {
	local LOG_FILE=$1
	local OUTSTREAM="/dev/null"
	local OPTIONS=
 	if [[ -n "${VERBOSE:-}" ]]; then
 		#shellcheck disable=SC2086
 		echo spawn ssh  ${SSH_PORT} ${VERBOSE_SSH} ${HE_RSA_SSH_KEY_OPTIONS} -o LogLevel=Error -o StrictHostKeyChecking=accept-new "${PRIVKEY_OPTION}" "${USER}@${TARGET_DEVICE}"  >&2
 	fi
 	if [[ -n "${VERBOSE_PORT_DISCOVERY:-}" ]]; then
 		OPTIONS="-d"
 		OUTSTREAM="/dev/stdout"
 	fi

	
	/usr/bin/expect ${OPTIONS} > ${OUTSTREAM} <<EOD
      set timeout 10

      spawn ssh  ${SSH_PORT} ${HE_RSA_SSH_KEY_OPTIONS} -o LogLevel=Error -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE}
	  send -- "\r"

      expect ".*#"
	  send -- "cat /etc/board.info | grep board.name | cut -d'=' -f2\r"
      expect ".*\r\n"
	  expect {
	  	"USW-Flex-XG\r\n" { 
		  expect -re ".*#"

		  send -- "telnet 127.0.0.1\r\r"
		  expect -re ".*#"
		  
		  send -- "terminal datadump\r"
		  expect -re ".*#"
		  
		  send -- "show run\r"
		  log_file -noappend ${LOG_FILE};
		  expect -re ".*#"
		  
		  send -- "exit\r"
		  log_file;
		  expect -re ".*#"

		  send -- "exit\r" 
		  expect eof
	  	}
	  	
	  	"USW-Aggregation\r\n" { 
		  expect -re ".*#"

		  send -- "cli\r"
		  expect -re ".*#"
		  
		  send -- "terminal length 0\r"
		  expect -re ".*#"
		  
		  send -- "show run\r"
		  log_file -noappend ${LOG_FILE};
		  expect -re ".*#"
		  
		  send -- "exit\r"
		  log_file;
		  expect -re ".*>"

		  send -- "exit\r"
		  expect -re ".*#"

		  
		  send -- "exit\r"
		  expect eof
		  
	  	}	  	
	  	
	  	"USW-Flex\r\n" {
		  log_file -noappend ${LOG_FILE};
		  send_log "interface 0/1\r\n"
		  send_log "description 'Port 1'\r\n"
		  send_log "interface 0/2\r\n"
		  send_log "description 'Port 2;\r\n"
		  send_log "interface 0/3\r\n"
		  send_log "description 'Port 3'\r\n"
		  send_log "interface 0/4\r\n"
		  send_log "description 'Port 4'\r\n"
		  log_file;
	  	 }

	  	-re ".*\r\n" {
		  send -- "telnet 127.0.0.1\r"
		  expect "(UBNT) >"
		  
		  send -- "enable\r"
		  expect "(UBNT) #"
		  
		  send -- "terminal length 0\r"
		  expect "(UBNT) #"
		  
		  send -- "show run\r"
		  log_file -noappend ${LOG_FILE};
		  expect "(UBNT) #"
		  
		  send -- "exit\r"
		  log_file;
		  expect "(UBNT) >"

		  send -- "exit\r"
		  expect ".*#"
		  
		  send -- "exit\r"
		  expect eof
		}
	}
EOD
	if [[ -f "$LOG_FILE" ]]; then 
		if [[ -n "${VERBOSE:-}" ]]; then
			echo "Show Run Begin:-----"
			cat "$LOG_FILE"
			echo "Show Run End:-----"
		fi
		#shellcheck disable=SC2002
		cat "$LOG_FILE" | tr -d '\r' | awk "$PORT_NAMES_AWK" > "${LOG_FILE}.jq"
		rm -f "$LOG_FILE" 2>/dev/null
	else
		if [[ -n "${VERBOSE:-}" ]]; then
			echo "** No Show Run output"
		fi	
	fi

}

function insertPortNamesIntoJson() {
	local JQ_PROGRAM=$1
	local JSON=$2
	if [[ -f "${JQ_PROGRAM}" ]]; then	
		if [[ -n "${VERBOSE:-}" ]]; then
			echo "JQ Program:"
			cat "${JQ_PROGRAM}"
		fi
		echo -n "${JSON}" | jq -r "$(cat "${JQ_PROGRAM}")"
		rm "$JQ_PROGRAM" 2>/dev/null
	else
		echo -n "${JSON}"
	fi
}


function usage() {

	local error="${1:-}"
	if [[ -n "${error}" ]]; then
		echo "${error}"
		echo
	fi
	
	cat <<- EOF
	Usage ${0}  -i privateKeyPath -p <passwordFilePath> -u user -v -d targetDevice [-t AP|SWITCH|SWITCH_FEATURE_DISCOVERY|SWITCH_DISCOVERY|UDMP|USG|CK|WIFI_SITE]
	  -i specify private public key pair path
	  -p specify password file path to be passed to sshpass -f. Note if both -i and -p are provided, the password file will be used
	  -u SSH user name for Unifi device
	  -d IP or FQDN for Unifi device
	  -o alternate port for SSH connection
	  -t Unifi device type
	  -v verbose and non compressed output
	  -w verbose output for port discovery
	  -o <timeout> max timeout (3s minimum)
	  -O echoes debug and timing info to /tmp/mcaDumpShort.log; errors are alwasy echoed to /tmp/mcaDumpShort.err
	  -V <jqExpression> Provide a JQ expression that must return a non empty output to validate the results. A json error is returned otherwiswe
	EOF
	exit 2
}

#------------------------------------------------------------------------------------------------

declare SSHPASS_OPTIONS=
declare PRIVKEY_OPTION=
declare PASSWORD_FILE_PATH=
declare VERBOSE_OPTION=
declare TIMEOUT=15
declare VERBOSE_SSH=
declare SSH_PORT=
declare TARGET_DEVICE_PORT=
declare logFile="/tmp/mcaDumpShort.log"
declare errFile="/tmp/mcaDumpShort.err"
declare ECHO_OUTPUT=


while getopts 'i:u:t:hd:vp:wm:o:OV:U:P:e' OPT
do
  case $OPT in
    i) PRIVKEY_OPTION="-i "${OPTARG} ;;
    u) USER=${OPTARG} ;;
    t) DEVICE_TYPE=${OPTARG} ;;
    d) TARGET_DEVICE=${OPTARG} ;;
    P) TARGET_DEVICE_PORT=${OPTARG} ;;
    v) VERBOSE=true ;;
    p) PASSWORD_FILE_PATH=${OPTARG} ;;
    w) VERBOSE_PORT_DISCOVERY=true ;;
    m) logFile=${OPTARG} ;;
    o) TIMEOUT=$(( OPTARG-1 )) ;;
    O) ECHO_OUTPUT=true ;;
    V) JQ_VALIDATOR=${OPTARG} ;;
    e) echo -n "$(errorJsonWithReason "simulated error")"; exit 1 ;;
    U)  if [[ -n "${OPTARG}" ]] &&  [[ "${OPTARG}" != "{\$UNIFI_VERBOSE_SSH}" ]]; then
    		VERBOSE_SSH="${OPTARG}"
    	fi ;;
    *) usage ;;
  esac
done

if [[ -n "${ECHO_OUTPUT:-}" ]]; then
	START_TIME=$(date +%s)
fi

if [[ -n "${VERBOSE:-}" ]]; then
        VERBOSE_OPTION="-v"
fi

if [[ -z "${TARGET_DEVICE:-}" ]]; then
	usage "Please specify a target device with -d"
fi

if [[ -z "${DEVICE_TYPE:-}" ]]; then
	usage "Please specify a device type with -t"
fi

if [[ "${TARGET_DEVICE_PORT}" == "{\$UNIFI_SSH_PORT}" ]]; then
	TARGET_DEVICE_PORT=""
fi
if [[ -n "${TARGET_DEVICE_PORT}" ]]; then
	if (( TARGET_DEVICE_PORT == 0 )) || (( TARGET_DEVICE_PORT < 0 )) || (( TARGET_DEVICE_PORT > 65535 )); then
		echo "Please specify a valid port with -P ($TARGET_DEVICE_PORT was specified)" >&2
		usage
	fi
	if (( TARGET_DEVICE_PORT != 10050 )); then
		SSH_PORT="-p ${TARGET_DEVICE_PORT}"
	fi
fi

if [[ -z "${USER:-}" ]]; then
	echo "Please specify a username with -u" >&2
	usage
fi

if [[ -z "${JQ_VALIDATOR:-}" ]]; then
	JQ_VALIDATOR=${VALIDATOR_BY_TYPE["${DEVICE_TYPE}"]:-}
fi

if [[ ${DEVICE_TYPE:-} == 'SWITCH_DISCOVERY' ]]; then
	JQ_PROGRAM="/tmp/unifiSWconf-${TARGET_DEVICE}"
	retrievePortNamesInto "$JQ_PROGRAM" &
fi

# {$UNIFI_SSHPASS_PASSWORD_PATH} means the macro didn't resolve in Zabbix
if [[ -n "${PASSWORD_FILE_PATH}" ]] && ! [[ "${PASSWORD_FILE_PATH}" == "{\$UNIFI_SSHPASS_PASSWORD_PATH}" ]]; then 
	if ! [[ -f "${PASSWORD_FILE_PATH}" ]]; then
		echo "Password file not found '$PASSWORD_FILE_PATH'"
		exit 1
	fi
	SSHPASS_OPTIONS="-f ${PASSWORD_FILE_PATH} ${VERBOSE_OPTION}"
	PRIVKEY_OPTION=
fi


if [[ ${DEVICE_TYPE:-} == 'AP' ]]; then
	JQ_OPTIONS='del (.port_table) | del(.radio_table[].scan_table) | del (.vap_table[].sta_table)'
elif [[ ${DEVICE_TYPE:-} == 'SWITCH' ]]; then
	JQ_OPTIONS='del (.port_table[].mac_table)'
elif [[ ${DEVICE_TYPE:-} == 'SWITCH_FEATURE_DISCOVERY' ]]; then
        JQ_OPTIONS="[ { power:  .port_table |  any (  .poe_power >= 0 ) ,\
	total_power_consumed_key_name: \"total_power_consumed\",\
	max_power_key_name: \"max_power\",\
	max_power: .total_max_power,\
	percent_power_consumed_key_name: \"percent_power_consumed\",\
	has_eth1: .has_eth1,\
	has_temperature: .has_temperature,\
	temperature_key_name: \"temperature\",\
        overheating_key_name: \"overheating\",\
	has_fan: .has_fan,\
	fan_level_key_name: \"fan_level\"
	} ]"
elif [[ ${DEVICE_TYPE:-} == 'UDMP' ]]; then
	JQ_OPTIONS='del (.dpi_stats) | del(.fingerprints) | del( .network_table[] |  select ( .address == null ))'
elif [[ ${DEVICE_TYPE:-} == 'USG' ]]; then
	JQ_OPTIONS='del (.dpi_stats) | del(.fingerprints) | del( .network_table[] |  select ( .address == null ))'
elif [[ ${DEVICE_TYPE:-} == 'CK' ]]; then
	JQ_OPTIONS='del (.dpi_stats)'
elif [[ ${DEVICE_TYPE:-} == 'SWITCH_DISCOVERY' ]]; then
	JQ_OPTIONS='del (.port_table[].mac_table)'
elif [[ -n "${DEVICE_TYPE:-}" ]]; then
	echo "Unknown device Type: '${DEVICE_TYPE:-}'"
	usage
fi
	


INDENT_OPTION="--indent 0"


if [[ -n "${VERBOSE:-}" ]]; then
	INDENT_OPTION=
    echo  "ssh ${SSH_PORT} ${HE_RSA_SSH_KEY_OPTIONS} -o LogLevel=Error -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE} mca-dump | jq ${INDENT_OPTION} ${JQ_OPTIONS:-}"
fi

declare EXIT_CODE=0
declare OUTPUT=
declare JSON_OUTPUT=
declare ERROR_FILE=/tmp/mca-$RANDOM.err
if [[ -n "${SSHPASS_OPTIONS:-}" ]]; then
	#shellcheck disable=SC2086
	OUTPUT=$(runWithTimeout "${TIMEOUT}" sshpass ${SSHPASS_OPTIONS} ssh ${SSH_PORT} ${VERBOSE_SSH} ${HE_RSA_SSH_KEY_OPTIONS} -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} "${USER}@${TARGET_DEVICE}" mca-dump 2> "${ERROR_FILE}")
else 
	#shellcheck disable=SC2086
	OUTPUT=$(runWithTimeout "${TIMEOUT}" ssh  ${SSH_PORT} ${VERBOSE_SSH} ${HE_RSA_SSH_KEY_OPTIONS} -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} "${USER}@${TARGET_DEVICE}" mca-dump  2> "${ERROR_FILE}")
fi
EXIT_CODE=$?
JSON_OUTPUT="${OUTPUT}"


if (( EXIT_CODE >=127 && EXIT_CODE != 255 )); then
	OUTPUT=$(errorJsonWithReason "time out with exit code $EXIT_CODE")
elif (( EXIT_CODE != 0 )) || [[ -z "${OUTPUT}" ]]; then
	OUTPUT=$(errorJsonWithReason "$(echo "error remote invoking mca-dump-short"; cat "${ERROR_FILE}"; echo "${OUTPUT}" )")
else
	if [[ -n "${JQ_VALIDATOR:-}" ]]; then
		VALIDATION=$(echo "${OUTPUT}" | jq "${JQ_VALIDATOR}")
		EXIT_CODE=$?
		if [[ -z "${VALIDATION}" ]] || [[ "${VALIDATION}" == "false" ]] || (( EXIT_CODE != 0 )); then
			OUTPUT=$(errorJsonWithReason "validationError: ${JQ_VALIDATOR}")
		fi
	fi
	if (( EXIT_CODE == 0 )); then
		errorFile="/tmp/jq$RANDOM$RANDOM.err"
		input=${OUTPUT}
		#shellcheck disable=SC2086
		OUTPUT=$(echo  "${input}" | jq ${INDENT_OPTION} "${JQ_OPTIONS}" 2> $errorFile)
		EXIT_CODE=$?
		if (( EXIT_CODE != 0 )) || [[ -z "${OUTPUT}" ]]; then
			OUTPUT=$(errorJsonWithReason "jq ${INDENT_OPTION} ${JQ_OPTIONS} returned status $EXIT_CODE; $(cat $errorFile); echo input was ${input}")
			EXIT_CODE=1
		fi
		rm $errorFile 2>/dev/null
	fi
fi
rm -f  "${ERROR_FILE}" 2>/dev/null

if (( EXIT_CODE == 0 )) && [[ ${DEVICE_TYPE:-} == 'SWITCH_DISCOVERY' ]]; then
	wait
	errorFile="/tmp/jq$RANDOM$RANDOM.err"
	OUTPUT=$(insertPortNamesIntoJson "$JQ_PROGRAM.jq" "${OUTPUT}"  2> $errorFile)
	CODE=$?
	if (( CODE != 0 )) || [[ -z "${OUTPUT}" ]]; then
		OUTPUT=$(errorJsonWithReason "insertPortNamesIntoJson failed; $(cat $errorFile)")
		EXIT_CODE=1
	fi
	rm $errorFile 2>/dev/null
fi

echo -n "${OUTPUT}"

if [[ -n "${ECHO_OUTPUT:-}" ]]; then
	END_TIME=$(date +%s)
	DURATION=$((  END_TIME - START_TIME   ))
	echo "$(date): ${TARGET_DEVICE}:${TARGET_DEVICE_PORT:-} ${DEVICE_TYPE} ${JQ_VALIDATOR:-} : ${DURATION}s - $EXIT_CODE" >> "${logFile}" 
	if [[ -n "${ECHO_OUTPUT:-}" ]]; then
		echo -n "${OUTPUT}" >> "${logFile}" 
		echo >> "${logFile}"
	fi
fi

if (( EXIT_CODE != 0 )); then
	echo "$(date) $TARGET_DEVICE" >> "${errFile}"
	echo "  ${OUTPUT}" >> "${errFile}"
	if [[ -n "${JSON_OUTPUT}" ]]; then
		echo "  ${JSON_OUTPUT}" >> "${errFile}"
	fi
fi

exit $EXIT_CODE



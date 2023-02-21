#!/usr/bin/env bash
set -uo pipefail

declare HE_RSA_SSH_KEY_OPTIONS='-o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa'

#AP|SWITCH|SWITCH_FEATURE_DISCOVERY|SWITCH_DISCOVERY|UDMP|USG|CK
declare -A VALIDATOR_BY_TYPE
VALIDATOR_BY_TYPE["AP"]=".vap_table? != null and .radio_table != null and ( .radio_table | map(select(.athstats.cu_total>0)) | length>0 ) "
VALIDATOR_BY_TYPE["UDMP"]=".network_table? != null"
VALIDATOR_BY_TYPE["USG"]="( .network_table? != null ) and ( .network_table | map(select(.mac!=null)) | length>0 )"
declare -A OPTIONAL_VALIDATOR_BY_TYPE
declare -A OPTION_MESSAGE
OPTIONAL_VALIDATOR_BY_TYPE["USG"]=" ( ( .[\"system-stats\"].temps | length ) == 4 ) "
OPTION_MESSAGE["USG"]="missingTemperatures"


#---------------------------------------------------------------------------------------
# Utilities

function runWithTimeout () { 
	local timeout=$1
	shift
	"$@" &
	local child=$!
	# Avoid default notification in non-interactive shell for SIGTERM
	trap -- "" SIGTERM
	local now; now=$(date +%s%N); now="${now:0:-6}"
	local endDate; endDate=$(( now + timeout*1000 ))
	local running=true
	( 	while (( now < endDate )) && [[ -n "${running}" ]];  
	  	do 
	  		sleep 0.1
			if ! ps -p ${child} > /dev/null; then
				running=
			fi
			now=$(date +%s%N); now="${now:0:-6}"
		done
		if [[ -n "${running}" ]]; then kill ${child} 2> /dev/null; fi
	) &
	wait ${child}
}


function errorJsonWithReason() {
	local reason; reason=$(echo "$1" | tr -d "\"'\n\r" )
	local t; t=$(date +"%T")
	echo '{ "at":"'"${t}"'", "r":"'"${reason}"'", "device":"'"${TARGET_DEVICE}"'", "mcaDumpError":"Error" }'
}

function insertWarningIntoJsonOutput() {
	local warning=$1
	local output=$2
	echo "${output}" | jq ". + { mcaDumpWarning: { \"${warning}\": true } }"
	echoErr "warning: $warning"
}

function echoErr() {
	local error=$1
	{
		echo "----------------------------------"
		echo "$(date) $TARGET_DEVICE"
		echo "  ${error}"
	} >> "${errFile}"
}

function issueSSHCommand() {
	local command=$*
 	if [[ -n "${VERBOSE:-}" ]]; then
 		#shellcheck disable=SC2086
 		echo ${SSHPASS_OPTIONS} ssh ${SSH_PORT} ${VERBOSE_SSH} ${HE_RSA_SSH_KEY_OPTIONS} ${BATCH_MODE} -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} "${USER}@${TARGET_DEVICE}" "$command"
 	fi
 	#shellcheck disable=SC2086
	${SSHPASS_OPTIONS} ssh ${SSH_PORT} ${VERBOSE_SSH} ${HE_RSA_SSH_KEY_OPTIONS} ${BATCH_MODE} -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} "${USER}@${TARGET_DEVICE}" "$command"
}

#---------------------------------------------------------------------------------------
# Fan Discovery

function fanDiscovery() {
	local -n exitCode=$1
	exitCode=0
	shift
	local sensors; sensors=$(issueSSHCommand sensors | grep -E "^fan[0-9]:" | cut -d' ' -f1)
	exitCode=$?
	if (( exitCode == 0 )); then
		local first=true
		echo -n "[ "
		for fan in $sensors; do
			if [[ -n "$fan" ]]; then 
				if [[ -z "$first" ]]; then echo -n ","; else first=; fi				
				echo -n "{ \"name\": \"${fan::-1}\" }"
			fi
		done
		echo -n " ]"
	fi
}

#---------------------------------------------------------------------------------------
# Switch Discovery


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





declare SWITCH_DISCOVERY_DIR="/tmp/unifiSwitchDiscovery"
function startSwitchDiscovery() {
	local jqProgram=$1
	local exp; exp=$(command -v expect)
	if [[ -z "${exp}" ]]; then exp=$(ls /usr/bin/expect); fi
	if [[ -z "${exp}" ]]; then 
		OUTPUT=$(errorJsonWithReason "please install 'expect' to run SWITCH_DISCOVERY")
		return 1
	else
		mkdir -p "${SWITCH_DISCOVERY_DIR}"
		#shellcheck disable=SC2034 
		# o=$(runWithTimeout 60 retrievePortNamesInto "${jqProgram}") &
		#	nohup needs a cmd-line utility
		#	nohup runWithTimeout 60 retrievePortNamesInto "${jqProgram}" &
		#(set -m; runWithTimeout 60 retrievePortNamesInto "${jqProgram}" &) &
		#runWithTimeout 60 retrievePortNamesInto "${jqProgram}" &
		runWithTimeout 60 retrievePortNamesInto "${jqProgram}" > /dev/null 2> /dev/null < /dev/null & disown
	fi
	return 0
}


function retrievePortNamesInto() {
	local logFile="$1-$RANDOM.log"
	local jqFile=$1
	local outStream="/dev/null"
	local options=
	#sleep $(( TIMEOUT + 1 )) # This ensures we leave the switch alone while mca-dump proper is processed;  the next invocation will find the result
 	if [[ -n "${VERBOSE:-}" ]]; then
 		#shellcheck disable=SC2086
 		echo ${SSHPASS_OPTIONS} spawn ssh  ${SSH_PORT} ${VERBOSE_SSH} ${HE_RSA_SSH_KEY_OPTIONS} -o LogLevel=Error -o StrictHostKeyChecking=accept-new "${PRIVKEY_OPTION}" "${USER}@${TARGET_DEVICE}"  >&2
 	fi
 	if [[ -n "${VERBOSE_PORT_DISCOVERY:-}" ]]; then
 		options="-d"
 		outStream="/dev/stdout"
 	fi

	#shellcheck disable=SC2086
	/usr/bin/expect ${options} > "${outStream}" <<EOD
      set timeout 30

      spawn ${SSHPASS_OPTIONS} ssh  ${SSH_PORT} ${HE_RSA_SSH_KEY_OPTIONS} -o LogLevel=Error -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE}
      
	  send -- "\r"

      expect ".*#"
	  send -- "cat /etc/board.info | grep board.name | cut -d'=' -f2\r"
      expect ".*\r\n"
	  expect {

	  	-re "(USW-Aggregation|USW-Flex-XG)\r\n" { 
		  expect -re ".*#"

		  send -- "cli\r"
		  expect -re ".*#"
		  
		  send -- "terminal length 0\r"
		  expect -re ".*#"

		  send -- "terminal datadump\r"
 		  expect -re ".*#"
		  
		  send -- "show run\r"
		  log_file -noappend ${logFile};
		  expect -re ".*#"
		  
		  send -- "exit\r"

	  	}	  	
	  	
	  	"USW-Flex\r\n" {
		  log_file -noappend ${logFile};
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
			expect { 
				"(UBNT) >" { 
					send -- "enable\r"
					expect "(UBNT) #" 

					send -- "terminal length 0\r"
					expect "(UBNT) #"

					send -- "show run\r" 
					log_file -noappend ${logFile};

					expect "(UBNT) #" 
					send -- "exit\r"

				} 
				"telnet: not found\r\n" { 
					send -- "cli\r"
					expect -re ".*#" 

					send -- "terminal length 0\r"
					expect -re ".*#" 

					send -- "show run\r" 
					log_file -noappend ${logFile};
					expect -re ".*#" 
				
					send "exit\r" 
				}
			}
		}
EOD
	local exitCode=$?
	if (( exitCode != 0 )); then
		{ 	echo "$(date) $TARGET_DEVICE"; 
			echo "  retrievePortNamesInto failed with code $exitCode";
			echo "Full command was mca-dump-short.sh $FULL_ARGS" 
			if [[ -f "$logFile" ]]; then 
				cat "$logFile"
			fi
		} >> "${errFile}"
		exit "${exitCode}"
	fi

	if [[ -f "$logFile" ]]; then 
		#shellcheck disable=SC2002
		cat "$logFile" | tr -d '\r' | awk "$PORT_NAMES_AWK" > "${jqFile}"
		rm -f "$logFile" 2>/dev/null
	else
		if [[ -n "${VERBOSE:-}" ]]; then
			echo "** No Show Run output"
		fi	
	fi

}

function insertPortNamesIntoJson() {
	local -n out=$1
	local jqProgramFile=$2
	local json=$3
	if [[ -f "${jqProgramFile}" ]]; then	
		if [[ -n "${VERBOSE:-}" ]]; then
			echo "jqProgramFile: "
			cat "${jqProgramFile}"
			echo; echo
		fi
		#shellcheck disable=SC2034
		out=$(echo "${json}" | jq -f "${jqProgramFile}" -r)
		#rm "$jqProgramFile" 2>/dev/null # we now leave it for the next guy
	else
		exit 2
	fi
}

#---------------------------------------------------------------------------------------------------------------------
# mca-dump invocation

function invokeMcaDump() {
	local deviceType=$1
	local jqProgram=$2
	local -n exitCode=$3
	local -n output=$4
	local -n jsonOutput=$5

	INDENT_OPTION="--indent 0"

	case "${deviceType:-}" in 

		AP) 							JQ_OPTIONS='del (.port_table) | del(.radio_table[]?.scan_table) | ( .vap_table[]|= ( .clientCount = ( .sta_table|length ) ) ) | del (.vap_table[]?.sta_table)' ;;
		SWITCH | SWITCH_DISCOVERY)		JQ_OPTIONS='del (.port_table[]?.mac_table)' ;;
		SWITCH_FEATURE_DISCOVERY)		JQ_OPTIONS="[ { power:  .port_table |  any (  .poe_power >= 0 ) ,\
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
												} ]" ;;
		UDMP| USG)						JQ_OPTIONS='del (.dpi_stats) | del(.fingerprints) | del( .network_table[]? |  select ( .address == null ))' ;;
		CK)								JQ_OPTIONS='del (.dpi_stats)' ;;
		*)								echo "Unknown device Type: '${DEVICE_TYPE:-}'"; usage ;;
	esac


	output=$(runWithTimeout "${TIMEOUT}" issueSSHCommand mca-dump  2> "${ERROR_FILE}")
	exitCode=$?
	#shellcheck disable=SC2034
	jsonOutput="${output}"


	if (( exitCode >=127 && exitCode != 255 )); then
		output=$(errorJsonWithReason "timeout ($exitCode)")
	elif (( exitCode != 0 )) || [[ -z "${output}" ]]; then
		output=$(errorJsonWithReason "$(echo "Remote pb: "; cat "${ERROR_FILE}"; echo "${output}" )")
		exitCode=1
	else
		if [[ -n "${JQ_VALIDATOR:-}" ]]; then
			VALIDATION=$(echo "${output}" | jq "${JQ_VALIDATOR}")
			exitCode=$?
			if [[ -z "${VALIDATION}" ]] || [[ "${VALIDATION}" == "false" ]] || (( exitCode != 0 )); then
				output=$(errorJsonWithReason "validationError: ${JQ_VALIDATOR}")
				exitCode=1
			fi
		fi
		if [[ -n "${JQ_OPTION_VALIDATOR:-}" ]]; then
			OPTION_VALIDATION=$(echo "${output}" | jq "${JQ_OPTION_VALIDATOR}")
			exitCode=$?
			if [[ -z "${OPTION_VALIDATION}" ]] || [[ "${OPTION_VALIDATION}" == "false" ]] || (( exitCode != 0 )); then				
				MESSAGE=${OPTION_MESSAGE["${DEVICE_TYPE}"]:-"unknownWarning"}
				output=$(insertWarningIntoJsonOutput "$MESSAGE" "$output")
			fi			
		fi		
		if (( exitCode == 0 )); then
			errorFile="/tmp/jq$RANDOM$RANDOM.err"
			jqInput=${output}
			output=
			#shellcheck disable=SC2086
			output=$(echo  "${jqInput}" | jq ${INDENT_OPTION} "${JQ_OPTIONS}" 2> "${errorFile}")
			exitCode=$?
			if (( exitCode != 0 )) || [[ -z "${output}" ]]; then
				output=$(errorJsonWithReason "jq ${INDENT_OPTION} ${JQ_OPTIONS} returned status $exitCode; $(cat $errorFile);  JQ input was ${jqInput}")
				exitCode=1
			fi
			rm "${errorFile}" 2>/dev/null
		fi
	fi
	rm -f  "${ERROR_FILE}" 2>/dev/null

	if (( exitCode == 0 )) && [[ "${DEVICE_TYPE:-}" == 'SWITCH_DISCOVERY' ]]; then
		# do not wait anymore for retrievePortNamesInto
		# this will ensure we don't time out, but sometimes we will use an older file
		# wait 
		errorFile="/tmp/jq${RANDOM}${RANDOM}.err"
		jqInput="${output}"
		output=
		insertPortNamesIntoJson output "${jqProgram}" "${jqInput}"  2> "${errorFile}"
		CODE=$?
		if (( CODE != 0 )) || [[ -z "${output}" ]]; then
			output=$(errorJsonWithReason "insertPortNamesIntoJson failed with error code $CODE; $(cat $errorFile)")
			exitCode=1
		fi
		rm "${errorFile}" 2>/dev/null
	fi
}


#------------------------------------------------------------------------------------------------


function usage() {

	local error="${1:-}"
	if [[ -n "${error}" ]]; then
		echo "${error}"
		echo
	fi
	
	cat <<- EOF
	Usage ${0}  -i privateKeyPath -p <passwordFilePath> -u user -v -d targetDevice [-t AP|SWITCH|SWITCH_FEATURE_DISCOVERY|SWITCH_DISCOVERY|UDMP|UDMP_FAN_DISCOVERY|UDMP_TEMP_DISCOVERY|USG|CK|WIFI_SITE]
	  -i specify private public key pair path
	  -p specify password file path to be passed to sshpass -f. Note if both -i and -p are provided, the password file will be used
	  -u SSH user name for Unifi device
	  -d IP or FQDN for Unifi device
	  -o alternate port for SSH connection
	  -t Unifi device type
	  -v verbose and non compressed output
	  -w verbose output for port discovery
	  -o <timeout> max timeout (3s minimum)
	  -O echoes debug and timing info to /tmp/mcaDumpShort.log; errors are always echoed to /tmp/mcaDumpShort.err
	  -V <jqExpression> Provide a JQ expression that must return a non empty output to validate the results. A json error is returned otherwise
	  -b run SSH in batch mode (do not ask for passwords)
	EOF
	exit 1
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
declare VERBOSE=
declare FULL_ARGS="$*"
declare BATCH_MODE=

while getopts 'i:u:t:hd:vp:wm:o:OV:U:P:eb' OPT
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
    b) BATCH_MODE="-o BatchMode=yes" ;;
    e) echo -n "$(errorJsonWithReason "simulated error")"; exit 1 ;;
    U)  if [[ -n "${OPTARG}" ]] &&  [[ "${OPTARG}" != "{\$UNIFI_VERBOSE_SSH}" ]]; then
    		VERBOSE_SSH="${OPTARG}"
    	fi ;;
    *) usage ;;
  esac
done

declare EXIT_CODE=0
declare OUTPUT=
declare JSON_OUTPUT=
declare ERROR_FILE=/tmp/mca-$RANDOM.err


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
declare JQ_OPTION_VALIDATOR=${OPTIONAL_VALIDATOR_BY_TYPE["${DEVICE_TYPE}"]:-}


# {$UNIFI_SSHPASS_PASSWORD_PATH} means the macro didn't resolve in Zabbix
if [[ -n "${PASSWORD_FILE_PATH}" ]] && ! [[ "${PASSWORD_FILE_PATH}" == "{\$UNIFI_SSHPASS_PASSWORD_PATH}" ]]; then 
	if ! [[ -f "${PASSWORD_FILE_PATH}" ]]; then
		echo "Password file not found '$PASSWORD_FILE_PATH'"
		exit 1
	fi
	SSHPASS_OPTIONS="sshpass -f ${PASSWORD_FILE_PATH} ${VERBOSE_OPTION}"
	PRIVKEY_OPTION=
fi

declare JQ_PROGRAM="${SWITCH_DISCOVERY_DIR}/switchPorts-${TARGET_DEVICE}.jq"
if [[ ${DEVICE_TYPE:-} == 'SWITCH_DISCOVERY' ]]; then
	startSwitchDiscovery "$JQ_PROGRAM"  # asynchronously discover port names
	EXIT_CODE=$?
fi

if (( EXIT_CODE == 0 )); then
	case "${DEVICE_TYPE}" in
		UDMP_FAN_DISCOVERY)	fanDiscovery EXIT_CODE OUTPUT JSON_OUTPUT ;;
		*)					invokeMcaDump "$DEVICE_TYPE" "$JQ_PROGRAM" EXIT_CODE OUTPUT JSON_OUTPUT ;;
	esac
fi


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
	echoErr " ${OUTPUT}\n  ${JSON_OUTPUT}" 
fi

echo "${OUTPUT}"


exit $EXIT_CODE



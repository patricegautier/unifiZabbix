#! /usr/local/bin/bash
# Requires bash v4.4 or above

# With many thanks to the folks who contributed to https://ubntwiki.com/products/software/unifi-controller/api

#DEBUG=2

GATEWAY_URL=https://gw99.gautiers.name

PID=$RANDOM

#----------------------------------------------
TMP_DIRECTORY=/tmp/unifiController-${PID}
mkdir ${TMP_DIRECTORY}
COOKIE_JAR=${TMP_DIRECTORY}/cookies.txt
HEADER_FILE=${TMP_DIRECTORY}/headers.txt

function cleanupAndExitWithMessageAndCode() {
	rm -fr ${TMP_DIRECTORY}
	if [[ $2 -ne 0 ]]; then
		echo "$1"
		echo "Exiting with status $2"
	fi		
	exit $2
}

#---------------------------------------------
# Debug Conveniences 

function _echovar() {
	L=$1
	shift
	if [[ -n "${DEBUG}" ]] && (( "${DEBUG}" >= $L )); then
		VARNAME=$1
		CONTEXT=$2
		VARVAL="${!VARNAME}"
		_echov $L "${CONTEXT}${CONTEXT:+:}${VARNAME}='${VARVAL}'"
	fi
}

function echovar() {
	if [[ -n "${DEBUG}" ]] && (( "${DEBUG}" >= 1 )); then
		_echovar 1 $*
	fi
}

function echovar2() {
	if [[ -n "${DEBUG}" ]] && (( "${DEBUG}" >= 2 )); then
		_echovar 2 $*
	fi
}

function _echov() {
	local L=$1
	shift
	if  [[ -n "${DEBUG}" ]] && (( "${DEBUG}" >= $L ))   ; then
		if (( "${DEBUG}" >=2 )); then
			echo "${BASHPID}: $@"  >&2
		else
			echo "$@"  >&2
		fi
	fi	
}

function echov() {
	if [[ -n "${DEBUG}"	]] && (( "${DEBUG}" >= 1 )); then
		_echov 1 "$*"
	fi
}

function traceOn {
	if [[ -n "${DEBUG}" ]] && (( "${DEBUG}" >= 2 )); then
		set -x
	fi
}

function traceOff {
	if [[ -n "${DEBUG}" ]] && (( "${DEBUG}" >= 2 )); then
		set +x
	fi
}


#------------------------------------------------

function issueControllerRequest() {

	local METHOD="-G"
	local OPTIND
	local OPTARG
	local OPT

	while getopts 'p' OPT
	do
		case $OPT in
			p) 	METHOD="-X" ;;
		esac
	done

	shift $((OPTIND-1))

	local URI=$1
	declare -n issueControllerRequest_RESPONSE=$2
	declare -n issueControllerRequest_RC=$3
	
	unset issueControllerRequest_RESPONSE
	unset issueControllerRequest_RC

	echovar2 URI issueControllerRequest
	echovar2 METHOD issueControllerRequest
	echovar2 GATEWAY_URL issueControllerRequest
		
	traceOn

	issueControllerRequest_RESPONSE=$(curl \
		"${METHOD}" \
		--silent \
		"${INSECURE}" \
		--cookie-jar "${COOKIE_JAR}" \
		--cookie "${COOKIE_JAR}" \
		--dump-header ${HEADER_FILE} \
		--header "Content-Type: application/json" \
		--header "accept: application/json" \
		--header "${CSRF_TOKEN}" \
		${GATEWAY_URL}/${URI} )
	set +x

	traceOff

	CSRF_TOKEN=$(grep -i "x-csrf-token" ${HEADER_FILE} | tr -d '\n\r')

		
	if [[ -n "${issueControllerRequest_RESPONSE}" ]]; then

		echovar2 issueControllerRequest_RESPONSE				
	
		if [[ "${issueControllerRequest_RESPONSE}" == "404" ]]; then
		   cleanupAndExitWithMessageAndCode	"${URI} returned 404" 1
		fi
		
		issueControllerRequest_RC=$(echo "${issueControllerRequest_RESPONSE}" | jq -r ".meta.rc")	
	fi
}

#------------------------------------------------

function issueAndParseControllerRequestWithJQPath() {

	local POST_OPTION
	local OPTIND
	local OPTARG
	local OPT
	
	while getopts 'p' OPT
	do
		case $OPT in
			p) 	POST_OPTION="-p" ;;
		esac
	done
	shift $((OPTIND-1))
 
	local SITE_NAME=$1
	local URI=$2
	local JQ_PATH=$3
	
	echovar2 SITE_NAME issueAndParseControllerRequestWithJQPath
	echovar2 URI issueAndParseControllerRequestWithJQPath
	echovar2 JQ_PATH issueAndParseControllerRequestWithJQPath
	
	local issueAndParseControllerRequestWithJQPath_CODE
	local issueAndParseControllerRequestWithJQPath_RESPONSE
	
	issueControllerRequest ${POST_OPTION} "${URI}" issueAndParseControllerRequestWithJQPath_RESPONSE issueAndParseControllerRequestWithJQPath_CODE
	
	if [[ "${issueAndParseControllerRequestWithJQPath_CODE}" == "ok" ]]; then	
	
		RESPONSE=$(echo "${issueAndParseControllerRequestWithJQPath_RESPONSE}")
		R=$?
		if [[ $? -ne 0 ]]; then
			cleanupAndExitWithMessageAndCode "Error retrieving response " $R
		fi
		if [[ -n "${JQ_PATH}" ]]; then
			RESPONSE=$(echo "${RESPONSE}" | jq -r "${JQ_PATH}")
		fi
		R=$?
		if [[ $? -ne 0 ]]; then
			cleanupAndExitWithMessageAndCode "Error applying JQ path ${JQ_PATH} to " $R
		fi
		
		
		if [[ -n "$4" ]]; then
			declare -n FULL_RESPONSE=$4
			FULL_RESPONSE="${issueAndParseControllerRequestWithJQPath_RESPONSE}"
		fi
		if [[ -n "${RESPONSE}" ]]; then
			echo "${RESPONSE}"
		else
			echo "Nothing parsed with path: '${JQ_PATH}' while processing ${URI}"
			echo "Response was '${issueAndParseControllerRequestWithJQPath_RESPONSE}'"
			cleanupAndExitWithMessageAndCode "" 1
		fi
		
	else
		echo "Error processing $URI"
		cleanupAndExitWithMessageAndCode "Response: '$issueAndParseControllerRequestWithJQPath_RESPONSE'" 1
	fi


}

#------------------------------------------------------------
function logout() {
	curl 	-X \
			--silent \
			"${INSECURE}" \
			--cookie-jar "${COOKIE_JAR}" \
			--cookie "${COOKIE_JAR}" \
			--header "Content-Type: application/json" \
			--header "accept: application/json" \
			--header "${CSRF_TOKEN}" \
			${GATEWAY_URL}/api/auth/logout 
}


#-----------------------------------------------------------

#TODO deal with /proxy/network for UDMPs vs CKs

usage() {
cat << EOF
Usage ${0} -u <username> -p <passwordFile> -g <gatewayURL> [-h] [-d] [-e int] [-c|-v|-i <siteName>:<path>:<jq_filter>] 

	-h: this text
	-e <int>: set debug level
	-d: equivalent to -e1

	-g: URL to a UnifiOS based controller, without a port, e.g: https://192.168.200.1
	-i: allow insecure connections
	-u: username to log into the controller (local user preferrably)
	-p: a file containing the password to log into the controller (local user preferrably)

	-s: output a list of sites maintained by the controller
	-c: output a JSON formatted list of client names and IPs in the default site
	-v: output a JSON formatted list of Ubiquiti devices names and IPs in the default site
	-r: provide a URI path to query the controller with and and jq filter to process the json with
			-v is the same as -i 'default:proxy/network/api/s/default/stat/device:.data[]|{name, ip}'
			-c is the same as -i 'default:proxy/network/api/s/default/stat/sta:.data[]|{name, ip}'
			-s is the same as -i 'default:proxy/network/api/self/sites:.data[].name'
	- if none of the previous 4 options are specified, the default is to list the sites under the controller, which is the same as -i

EOF
exit 1
}

function parseSiteNamePathAndFilter() {
	declare -n _parsePathAndFilter_SITE_NAME=$2
	declare -n _parsePathAndFilter_PATH=$3
	declare -n _parsePathAndFilter_FILTER=$4
	_parsePathAndFilter_SITE_NAME=$(echo $1 | awk -F: '{ print $1}')
	_parsePathAndFilter_PATH=$(echo $1 | awk -F: '{ print $2}')
	_parsePathAndFilter_FILTER=$(echo $1 | awk -F: '{ print $3}')
	if [[ -z "${_parsePathAndFilter_SITE_NAME}" ]] || [[ -z "${_parsePathAndFilter_PATH}" ]] || [[ -z "${_parsePathAndFilter_FILTER}" ]]; then
		echo "Could not parse $1"
		exit 1
	else
		echovar _parsePathAndFilter_SITE_NAME
		echovar _parsePathAndFilter_PATH
		echovar _parsePathAndFilter_FILTER
	fi
}

while getopts 'dhe:cvg:u:p:sr:i' OPT
do
  case $OPT in
    d) 	DEBUG=1 ;;
    e) 	DEBUG=${OPTARG} ;;
    h) 	usage ;;
    
    c) 	COMMAND_SITE_NAME='default'
    	COMMAND_URI_PATH='proxy/network/api/s/default/stat/sta'
       	COMMAND_JQ_FILTER='.data[]|{name, ip}';;
       	
    v) 	COMMAND_SITE_NAME='default'
    	COMMAND_URI_PATH='proxy/network/api/s/default/stat/device'
       	COMMAND_JQ_FILTER='.data[]|{name, ip}' ;;
       	
    r) 	parseSiteNamePathAndFilter "${OPTARG}" COMMAND_SITE_NAME COMMAND_URI_PATH COMMAND_JQ_FILTER ;;
    
	s)  COMMAND_URI_PATH='proxy/network/api/self/sites'
		COMMAND_JQ_FILTER='.data[].name' 
		COMMAND_SITE_NAME='default' ;;
		
		
    g) 	GATEWAY_URL=${OPTARG} ;;
    u) 	USERNAME=${OPTARG} ;;
    p) 	PASSWORD_FILE=${OPTARG} ;;
    i)	INSECURE="--insecure" ;;
    *) 	usage ;;
  esac
done

if [[ -z "${GATEWAY_URL}" ]]; then
	echo "Missing Gateway - specify with -g"
	usage
fi
if [[ -z "${USERNAME}" ]]; then
	echo "Missing Username - specify with -u"
	usage
fi
if [[ -z "${PASSWORD_FILE}" ]]; then
	echo "Missing password file - specify with -p"
	usage
fi


LOGIN=$(curl --include --silent  "${INSECURE}" --cookie ${COOKIE_JAR} ${GATEWAY_URL})
S=$?
if [[ $S -ne 0 ]]; then
	echo "Could not communicate with ${GATEWAY_URL} - curl returned $S"
	exit 1
fi

echovar2 LOGIN

CSRF_TOKEN=$(echo "$LOGIN" | grep -i "x-csrf-token" | tr -d '\n\r')
echovar CSRF_TOKEN

if [[ -z "${CSRF_TOKEN}" ]]; then
	cleanupAndExitWithMessageAndCode "No CSRF token" 1
fi

LOGIN_RESPONSE_JSON=${TMP_DIRECTORY}/login.json
echovar LOGIN_RESPONSE_JSON
LOGIN_RESPONSE=${TMP_DIRECTORY}/login.txt

traceOn


PASSWORD=$(<${PASSWORD_FILE})
if [[ -z "${PASSWORD}" ]]; then
	echo "Couldn't get password from ${PASSWORD_FILE}"
fi


DATA='{"username":"'${USERNAME}'" ,"password":"'"${PASSWORD}"'" ,"rememberMe":false}'
echovar2 DATA

LOGIN_RESPONSE_CODE=$(curl \
	--silent \
	"${INSECURE}" \
	--header ${CSRF_TOKEN} \
	--cookie-jar "${COOKIE_JAR}" \
	--cookie "${COOKIE_JAR}" \
	--header "Content-Type: application/json" \
	--data "${DATA}" \
	--output ${LOGIN_RESPONSE_JSON} \
	${GATEWAY_URL}/api/auth/login ) > ${LOGIN_RESPONSE}

traceOff

echovar2 LOGIN_RESPONSE_CODE


ERROR=$(echo "${LOGIN_RESPONSE_CODE}" | jq -r ".errors?")

if [[ -n "${ERROR}" ]] && [[ "${ERROR}" != "null" ]]; then
	cleanupAndExitWithMessageAndCode "Could not log in: ${ERROR}" 1
fi


echov "Login Successful"
if [[ -z "${COMMAND_URI_PATH}" ]]; then

	COMMAND_URI_PATH='proxy/network/api/self/sites'
	COMMAND_JQ_FILTER=".data[].name"
	COMMAND_SITE_NAME="''"

fi

issueAndParseControllerRequestWithJQPath "${COMMAND_SITE_NAME}" "${COMMAND_URI_PATH}" "${COMMAND_JQ_FILTER}"

	# can't seem to find the logout path
#	issueAndParseControllerRequestWithJQPath -p "default" "api/logout"  > /dev/null

# Can't seem to figure out the logout API
# the gateway logs say 2021-11-27T22:01:01.493Z - error: [https] 3ms 501 --silent /api/logout
# 501 return status
#	logout
	

cleanupAndExitWithMessageAndCode

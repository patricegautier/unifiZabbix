#! /usr/local/bin/bash
# Requires bash v4.4 or above

# With many thanks to the folks who contributed to https://ubntwiki.com/products/software/unifi-controller/api
# and https://github.com/Art-of-WiFi/UniFi-API-client/blob/master/src/Client.php
#

#DEBUG=2

GATEWAY_URL=https://gw99.gautiers.name

PID=$RANDOM

#----------------------------------------------
TMP_DIRECTORY=/tmp/unifiController-${PID}
mkdir -p ${TMP_DIRECTORY} ||  ( echo "Could not create temp directory ${TMP_DIRECTORY}";  exit 1 )
COOKIE_JAR=${TMP_DIRECTORY}/cookies.txt

function cleanupAndExitWithMessageAndCode() {
	if [[ -z "${DEBUG}" ]]; then  rm -fr ${TMP_DIRECTORY}; fi
	if [[ $2 -ne 0 ]]; then
		echo "$1"
		echo "Exiting with status $2" >2&
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


function echov2() {
	if [[ -n "${DEBUG}"	]] && (( "${DEBUG}" >= 2 )); then
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

# ------------------------------

#     protected function create_x_csrf_token_header()
#     {
#         if (!empty($this->cookies) && strpos($this->cookies, 'TOKEN') !== false) {
#             $cookie_bits = explode('=', $this->cookies);
#             if (empty($cookie_bits) || !array_key_exists(1, $cookie_bits)) {
#                 return;
#             }
# 
#             $jwt_components = explode('.', $cookie_bits[1]);
#             if (empty($jwt_components) || !array_key_exists(1, $jwt_components)) {
#                 return;
#             }
# 
#             $this->curl_headers[] = 'x-csrf-token: ' . json_decode(base64_decode($jwt_components[1]))->csrfToken;
#         }
#     }

# if the method not GET, then the CSRF header has to be retrieved from the token cookies

function getCSRFTokenFromCookies() {

	local TOKEN_COOKIE=$(cat ${COOKIE_JAR} | grep TOKEN)
	TOKEN_COUNT=$(echo "${TOKEN_COOKIE}" | wc -l)
	if (( $TOKEN_COUNT != 1)); then cleanupAndExitWithMessageAndCode "Unexpected TOKEN cookie count $TOKEN_COUNT" 1; fi

	TOKEN_VALUE=$(echo "${TOKEN_COOKIE}" | awk -F'\t' '{print $7}')
	if (( $? != 0 )); then cleanupAndExitWithMessageAndCode "Couldn't get token value'" 1; fi
	echovar2 TOKEN_VALUE

	CSRF_VALUE=$(echo "${TOKEN_VALUE}" | awk -F'.' '{print $2}')
	if (( $? != 0 )); then cleanupAndExitWithMessageAndCode "Couldn't get CSRF_VALUE from ${TOKEN_VALUE}'" 1; fi
	echovar2 CSRF_VALUE

	CSRF_DECODED_VALUE=$(echo "${CSRF_VALUE}" | base64 -d)
	#There seems to be inconsistent handling here for base64 so ignoring error codes
	#if (( $? != 0 )); then cleanupAndExitWithMessageAndCode "Couldn't decode ''${CSRF_VALUE}'" 1; fi

	# For reasons unscrutable, the value I get from the cookie is missing a final }, so I add it below
	if [[ ${CSRF_DECODED_VALUE: -1} != '}'  ]]; then CSRF_DECODED_VALUE+='}'; fi
	echovar2 CSRF_DECODED_VALUE		

	CSRF_TOKEN=$(echo "${CSRF_DECODED_VALUE}" | jq -r ".csrfToken")
	if (( $? != 0 )); then cleanupAndExitWithMessageAndCode "Couldn't extract CSRF token  from ${CSRF_DECODED_VALUE}'" 1; fi
	echovar2 CSRF_TOKEN

	echo "x-csrf-token: ${CSRF_TOKEN}"
}


#------------------------------------------------
# Usage issueControllerRequest [-p] [-X <http method>] [-d <data to PUT]


function issueControllerRequest() {

	local METHOD="-G"
	local OPTIND
	local OPTARG
	local OPT
	local issueControllerRequestDATA

	while getopts 'pX:D:' OPT
	do
		case $OPT in
			X)	METHOD="-X ${OPTARG}" ;;
			D)	issueControllerRequestDATA="${OPTARG}" ;;
			?)	echo "Unkown Option $OPT"
				exit 1 ;;
		esac
	done

	shift $((OPTIND-1))

	local URI=$1
	declare -n issueControllerRequest_RESPONSE=$2
	declare -n issueControllerRequest_RC=$3
	
	unset issueControllerRequest_RESPONSE
	unset issueControllerRequest_RC

	echovar2 URI
	echovar2 METHOD
	echovar2 GATEWAY_URL	
	
	CONTROLLER_REQUEST_OUTPUT_FILE=${TMP_DIRECTORY}/request-$RANDOM.txt
	HEADER_FILE=${TMP_DIRECTORY}/headers-$RANDOM.txt



	if [[ -n "${METHOD}" ]]; then
		CSRF_TOKEN=$(getCSRFTokenFromCookies)
		if (( $? !=0 )); then 
			cleanupAndExitWithMessageAndCode "Could retrieve CSRF from cookies: $?"
		fi
		echov2 "New CSRF from cookies: $CSRF_TOKEN"
	fi

	traceOn
	local CURL_RESPONSE=$(curl \
		-w "%{http_code}\n" \
		${METHOD} \
		--silent \
		${INSECURE} \
		--cookie-jar "${COOKIE_JAR}" \
		--cookie "${COOKIE_JAR}" \
		--header "Content-Type: application/json" \
		--header "accept: application/json" \
		--header "${CSRF_TOKEN}" \
 		--data "${issueControllerRequestDATA}" \
		--dump-header ${HEADER_FILE} \
		--output "${CONTROLLER_REQUEST_OUTPUT_FILE}" \
		${GATEWAY_URL}/${URI} )
	S=$?
	traceOff

	if [[ $S -ne 0 ]]; then
		echo "Could not query controller at ${GATEWAY_URL} with ${URI} - curl returned $S"
		exit 1
	fi

	issueControllerRequest_RESPONSE=$(cat ${CONTROLLER_REQUEST_OUTPUT_FILE})
	if [[ "${CURL_RESPONSE:0:1}" != "2" ]]; then
		cat "${CONTROLLER_REQUEST_OUTPUT_FILE}"
		echo
		cleanupAndExitWithMessageAndCode	"${URI} returned ${CURL_RESPONSE}" 1
	fi

	local CSRF_NEW_TOKEN=$(cat "${CONTROLLER_REQUEST_OUTPUT_FILE}" | grep -i "x-csrf-token" | tr -d '\n\r')
	echovar2 CSRF_NEW_TOKEN
	CSRF_TOKEN=${CSRF_NEW_TOKEN:-${CSRF_TOKEN}}
	echovar2 CSRF_TOKEN
	

	issueControllerRequest_RC=$(echo "${issueControllerRequest_RESPONSE}" | jq -r ".meta.rc")	

}

#------------------------------------------------

function issueAndParseControllerRequestWithJQPath() {

	local POST_OPTION
	local OPTIND
	local OPTARG
	local OPT
	local DATA
	
	while getopts 'pX:D:' OPT
	do
		case $OPT in
			p) 	POST_OPTION="-p" ;;
			X)	POST_OPTION="-X ${OPTARG}" ;;
			D)	DATA="${OPTARG}"
		esac
	done
	shift $((OPTIND-1))
 
	local SITE_NAME=$1
	local URI=$2
	local JQ_PATH=$3
	
	echovar2 SITE_NAME issueAndParseControllerRequestWithJQPath
	echovar2 URI issueAndParseControllerRequestWithJQPath
	echovar2 JQ_PATH issueAndParseControllerRequestWithJQPath
	echovar2 DATA  issueAndParseControllerRequestWithJQPath
	
	local issueAndParseControllerRequestWithJQPath_CODE
	local issueAndParseControllerRequestWithJQPath_RESPONSE
	
	issueControllerRequest ${POST_OPTION} -D "${DATA}" "${URI}" issueAndParseControllerRequestWithJQPath_RESPONSE issueAndParseControllerRequestWithJQPath_CODE
	
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
			echo "Nothing parsed with path: '${JQ_PATH}' while processing ${URI}" >2&
			echo "Response was '${issueAndParseControllerRequestWithJQPath_RESPONSE}'" >2&
			echo "{}"
			cleanupAndExitWithMessageAndCode
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
Usage ${0} -u <username> -p <passwordFile> -g <gatewayURL> [-c|-v|-i <siteName>:<path>:<jq_filter>] 
	Issues a GET to the specified path
${0} -u <username> -p <passwordFile> -g <gatewayURL>  [-D <data>] [-P <siteName>:<path>]
	Issues a PUT to the specified path with the specified data
${0} -u <username> -p <passwordFile> -g <gatewayURL> [-X <siteName>:<path>] 
	Issues a DELETE to the specified path

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
	-a: output a JSON formatted list of Ubiquiti devices and client names with IPs in the default site
	-r: provide a URI path to query the controller with and and jq filter to process the json with
			-v is the same as -r 'default:proxy/network/api/s/default/stat/device:.data[]|{name, ip}'
			-c is the same as -r 'default:proxy/network/api/s/default/stat/sta:.data[]|{name, ip}'
			-s is the same as -r 'default:proxy/network/api/self/sites:.data[].name'
	-P: PUTs data specified with -D to the specified path
	-X: issues a DELETE to the specified path
	
	- if none of the previous options are specified, the default is to list the sites under the controller, which is the same as -s

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
		echo "Could not parse $1;  Expected <siteName>:<path>:<jq_filter>"
		exit 1
	else
		echovar _parsePathAndFilter_SITE_NAME
		echovar _parsePathAndFilter_PATH
		echovar _parsePathAndFilter_FILTER
	fi
}

function parseSiteNameAndPath() {
	declare -n _parsePathAndFilter_SITE_NAME=$2
	declare -n _parsePathAndFilter_PATH=$3
	_parsePathAndFilter_SITE_NAME=$(echo $1 | awk -F: '{ print $1}')
	_parsePathAndFilter_PATH=$(echo $1 | awk -F: '{ print $2}')
	if [[ -z "${_parsePathAndFilter_SITE_NAME}" ]] || [[ -z "${_parsePathAndFilter_PATH}" ]]; then
		echo "Could not parse $1;  Expected <siteName>:<path>"
		exit 1
	else
		echovar _parsePathAndFilter_SITE_NAME
		echovar _parsePathAndFilter_PATH
	fi
}

while getopts 'dhe:cvg:u:p:sr:iaP:D:X:' OPT
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
       	
    a)  COMMAND_SITE_NAME='default'
    	COMMAND_URI_PATH='proxy/network/api/s/default/stat/device'
       	COMMAND_JQ_FILTER='.data[]|{name, ip}'
		ADD_CLIENTS=true ;; 
       	
    r) 	parseSiteNamePathAndFilter "${OPTARG}" COMMAND_SITE_NAME COMMAND_URI_PATH COMMAND_JQ_FILTER ;;
    
	s)  COMMAND_URI_PATH='proxy/network/api/self/sites'
		COMMAND_JQ_FILTER='.data[].name' 
		COMMAND_SITE_NAME='default' ;;
		
		
    g) 	GATEWAY_URL=${OPTARG} ;;
    u) 	USERNAME=${OPTARG} ;;
    p) 	PASSWORD_FILE=${OPTARG} ;;
    i)	INSECURE="--insecure" ;;
    
    D)	PUT_DATA="${OPTARG}" ;;
    P)	parseSiteNameAndPath "${OPTARG}" COMMAND_SITE_NAME COMMAND_URI_PATH
    	PUT=true ;;

    X)	parseSiteNameAndPath "${OPTARG}" COMMAND_SITE_NAME COMMAND_URI_PATH
    	DELETE=true ;;

    
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

echov --------------------- Creating Session

LOGIN=$(curl --include --silent  ${INSECURE} --cookie ${COOKIE_JAR} ${GATEWAY_URL})
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


echov --------------------- Logging in


LOGIN_RESPONSE_FILE=${TMP_DIRECTORY}/loginResponse.txt
echovar2 LOGIN_RESPONSE_FILE

PASSWORD=$(<${PASSWORD_FILE})
if [[ -z "${PASSWORD}" ]]; then
	echo "Couldn't get password from ${PASSWORD_FILE}"
fi

LOGIN_DATA='{"username":"'${USERNAME}'" ,"password":"'"${PASSWORD}"'" ,"rememberMe":false}'
echovar2 DATA

traceOn

LOGIN_RESPONSE_CODE=$(curl \
	--silent \
	${INSECURE} \
	--header "${CSRF_TOKEN}" \
	--cookie-jar "${COOKIE_JAR}" \
	--cookie "${COOKIE_JAR}" \
	--header "Content-Type: application/json" \
	--data "${LOGIN_DATA}" \
	--output ${LOGIN_RESPONSE_FILE} \
	${GATEWAY_URL}/api/auth/login )

traceOff

S=$?
if [[ $S -ne 0 ]]; then
	echo "Could not log into ${GATEWAY_URL} - curl returned $S"
	exit 1
fi

echovar2 LOGIN_RESPONSE_CODE

ERROR=$(echo "${LOGIN_RESPONSE_CODE}" | jq -r ".errors?")
if [[ -n "${ERROR}" ]] && [[ "${ERROR}" != "null" ]]; then
	cleanupAndExitWithMessageAndCode "Could not log in: ${ERROR}" 1
fi
echov "Login Successful"


CSRF_NEW_TOKEN=$(cat "${LOGIN_RESPONSE_FILE}" | grep -i "x-csrf-token" | tr -d '\n\r')
echovar2 CSRF_NEW_TOKEN
CSRF_TOKEN=${CSRF_NEW_TOKEN:-${CSRF_TOKEN}}
echovar2 CSRF_TOKEN



if [[ -n "${PUT}" ]]; then 

	echov --------------------- Putting Data
	echovar2 PUT_DATA
	issueAndParseControllerRequestWithJQPath -X "PUT" -D "${PUT_DATA}" "${COMMAND_SITE_NAME}" "${COMMAND_URI_PATH}" "."

elif [[ -n "${DELETE}" ]]; then 

	echov --------------------- Delete Data
	issueAndParseControllerRequestWithJQPath -X "DELETE" "${COMMAND_SITE_NAME}" "${COMMAND_URI_PATH}" "."


else


	if [[ -z "${COMMAND_URI_PATH}" ]]; then
		COMMAND_URI_PATH='proxy/network/api/self/sites'
		COMMAND_JQ_FILTER=".data[].name"
		COMMAND_SITE_NAME="''"
	fi

	echov --------------------- Getting Data
	issueAndParseControllerRequestWithJQPath "${COMMAND_SITE_NAME}" "${COMMAND_URI_PATH}" "${COMMAND_JQ_FILTER}"

	if [[ -n "${ADD_CLIENTS}" ]]; then
		COMMAND_URI_PATH='proxy/network/api/s/default/stat/sta'
		echov --------------------- Getting Data \#2
		issueAndParseControllerRequestWithJQPath "${COMMAND_SITE_NAME}" "${COMMAND_URI_PATH}" "${COMMAND_JQ_FILTER}"
	fi

fi

	# can't seem to find the logout path
#	issueAndParseControllerRequestWithJQPath -p "default" "api/logout"  > /dev/null

# Can't seem to figure out the logout API
# the gateway logs say 2021-11-27T22:01:01.493Z - error: [https] 3ms 501 --silent /api/logout
# 501 return status
#	logout
	

cleanupAndExitWithMessageAndCode

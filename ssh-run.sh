#!/bin/bash
# set -x

usage()
{
	cat << EOF
Usage ${0}  -i privateKeyPath -p <passwordFilePath> -u user -v -d targetDevice <command-to-run>
	-i specify private public key pair path
	-p specify password file path to be passed to sshpass -f. Note if both -i and -p are provided, the password file will be used
	-u SSH user name for Unifi device
	-d IP or FQDN for Unifi device
	-v verbose and non compressed output
EOF
	exit 2
}

SSHPASS_OPTIONS=
PRIVKEY_OPTION=
PASSWORD_FILE_PATH=
VERBOSE_OPTION=


while getopts 'i:u:hd:vp:' OPT
do
  case $OPT in
    i) PRIVKEY_OPTION="-i "${OPTARG} ;;
    u) USER=${OPTARG} ;;
    d) TARGET_DEVICE=${OPTARG} ;;
    v) VERBOSE=true ;;
    p) PASSWORD_FILE_PATH=${OPTARG} ;;
    h) usage ;;
  esac
done

shift $((OPTIND-1))
REMOTE_COMMAND=$@

if ! [[ -z ${VERBOSE} ]]; then
        VERBOSE_OPTION="-v"
fi

# {$UNIFI_SSHPASS_PASSWORD_PATH} means the macro didn't resolve in Zabbix
if ! [[ -z ${PASSWORD_FILE_PATH} ]] && ! [[ ${PASSWORD_FILE_PATH} == "{\$UNIFI_SSHPASS_PASSWORD_PATH}" ]]; then 
	SSHPASS_OPTIONS="-f "${PASSWORD_FILE_PATH}" "${VERBOSE_OPTION}
	PRIVKEY_OPTION=
fi


if ! [[ -z ${VERBOSE} ]]; then
    	echo ${SSHPASS_COMMAND} 'ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new ' ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE} ${REMOTE_COMMAND}
fi


if ! [[ -z ${SSHPASS_OPTIONS} ]]; then
	sshpass ${SSHPASS_OPTIONS} ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE} "${REMOTE_COMMAND}"
else
	ssh -o LogLevel=Error -o StrictHostKeyChecking=accept-new ${PRIVKEY_OPTION} ${USER}@${TARGET_DEVICE} "${REMOTE_COMMAND}"
fi




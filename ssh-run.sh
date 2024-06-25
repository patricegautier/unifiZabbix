#!/usr/bin/env bash
# set -x
set -uo pipefail

usage() {
	cat << EOF
Usage ${0}  -i privateKeyPath -p <passwordFilePath> -u user -v -d targetDevice <command-to-run>
	-i specify private public key pair path
	-p specify password file path to be passed to sshpass -f. Note if both -i and -p are provided, the password file will be used
	-u SSH user name for Unifi device
	-d IP or FQDN for Unifi device
	-v verbose and non compressed output
	-r explicitly allow RSA (for legacy devices, i.e Airmaxes)
	-n empty option, to provide a default for zabbix key expansion
EOF
	exit 2
}

declare SSHPASS_OPTIONS=
declare PRIVKEY_OPTION=
declare PASSWORD_FILE_PATH=
declare SSH_OPTIONS="-o LogLevel=Error -o StrictHostKeyChecking=accept-new"

while getopts 'i:u:hd:vp:rn' OPT
do
  case $OPT in
    i) PRIVKEY_OPTION="-i "${OPTARG} ;;
    u) USER=${OPTARG} ;;
    d) TARGET_DEVICE=${OPTARG} ;;
    v) VERBOSE="-v" ;;
    p) PASSWORD_FILE_PATH=${OPTARG} ;;
    r) SSH_OPTIONS+=" -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa" ;;
    n) true ;;
    *) usage ;;
  esac
done

shift $((OPTIND-1))
declare -a REMOTE_COMMAND=( "$@ ")

# {$UNIFI_SSHPASS_PASSWORD_PATH} means the macro didn't resolve in Zabbix
if [[ -n "${PASSWORD_FILE_PATH}" ]] && [[ "${PASSWORD_FILE_PATH}" != "{\$UNIFI_SSHPASS_PASSWORD_PATH}" ]]; then 
	SSHPASS_OPTIONS="-f ${PASSWORD_FILE_PATH} ${VERBOSE:-}"
	PRIVKEY_OPTION=
fi

if [[ -n "${VERBOSE:-}" ]]; then
	# shellcheck disable=SC2086
   	echo "${SSHPASS_COMMAND}" ssh ${SSH_OPTIONS} ${PRIVKEY_OPTION} "${USER}@${TARGET_DEVICE}" "${REMOTE_COMMAND[@]}"
fi

if [[ -n "${SSHPASS_OPTIONS}" ]]; then
	# shellcheck disable=SC2086
	sshpass "${SSHPASS_OPTIONS}" ssh ${SSH_OPTIONS} ${PRIVKEY_OPTION} "${USER}@${TARGET_DEVICE}" "${REMOTE_COMMAND[@]}"
else
	# shellcheck disable=SC2086,SC2029
	ssh ${SSH_OPTIONS} ${PRIVKEY_OPTION} "${USER}@${TARGET_DEVICE}" "${REMOTE_COMMAND[@]}"
fi

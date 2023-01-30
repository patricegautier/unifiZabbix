#!/bin/bash
# set -x

usage()
{
cat << EOF
Usage "${0}" [-d] [-R] [-i privateKeyPath] [-s <fileName>] [-u user] user@targetMachine
	-i specify private public key pair
	-s use sshpass with given password file. Will ask for the password if sshpass is not installed
	-d disable strict host key checking with SSH option StrictHostKeyChecking=no
	-b for dropbear (used in protect cameras) additionally copy ~/.ssh/authorized_keys to /var/etc/dropbear
	-u run the command as <user>
	-R remove the local authorized key for that host
	-4 force ipv4
	-n no ping - do not preflight with ping
	-B bind interface for ssh
EOF
	exit 2
}

STRICT=""
unset DROPBEAR
unset SUDO_USER
unset IPV4
unset REMOVE_KEY
unset TARGET
unset PRIVKEY_PATH
unset SSH_PASS_FILE

while getopts 'i:s:dbu:4RhnB:' OPT
do
  case $OPT in
    i) PRIVKEY_PATH=${OPTARG} ;;
    s) SSH_PASS_FILE=${OPTARG} ;;
    d) STRICT="-o StrictHostKeyChecking=no" ;;
    b) DROPBEAR=true ;;
    u) SUDO_USER="sudo -u "${OPTARG} ;;
    4) IPV4="-4" ;;
    R) REMOVE_KEY=true;;
    n) NOPING=true;;
    B) BIND_INTERFACE_OPTION="-B ${OPTARG}" ;;
    *) usage ;;
  esac
done

shift $((OPTIND-1))


TARGET=$*


if [[ -z ${TARGET} ]]; then
	usage
fi


if [[ -z ${PRIVKEY_PATH} ]]; then
   	PRIVKEY_PATH=${HOME}"/.ssh/id_rsa"
fi

PUBKEY_PATH=${PRIVKEY_PATH}".pub"
PUBKEY=$(<"${PUBKEY_PATH}") || exit 1;

if [[ -z "${PUBKEY}" ]]; then
	echo "Could not read public key at ${PUBKEY_PATH}"
	exit 1
fi

HOST=$(echo "${TARGET}" | awk -F'@' '{print $2}')

if [[ -z "${HOST}" ]]; then
	echo "Could not parse host from entry: ${TARGET}"
	echo "expected user@host"
	exit 1
fi

if [[ -n "${REMOVE_KEY}" ]]; then
	ssh-keygen -R "${HOST}" || exit 1
fi

if [[ -z "${NOPING}" ]]; then
	#echo "HOST = $HOST"
	#set -x
	# Quick check to see if it is pingable
	trap - SIGALRM
	ping -c 1 -t 5 "${HOST}" >> /dev/null
	R=$?
	if ! [[ $R -eq 0 ]]; then
		echo "${HOST} is not reachable - ping returned $R"
		exit 1
	fi
fi

#shellcheck disable=SC2086
${SUDO_USER} ssh ${BIND_INTERFACE_OPTION} ${IPV4} -i "${PRIVKEY_PATH}" -q -o "BatchMode yes" "${TARGET}" true
PUBKEY_OK=$?
SSHPASS=$(command -v sshpass)

if [ ${PUBKEY_OK} != '0'  ]; then
	echo "Need to update public key for ${TARGET}"
	unset DROPBEAR_CMD
   	if [[ -n "${DROPBEAR}" ]]; then
	   	DROPBEAR_CMD=" && cp .ssh/authorized_keys /var/etc/dropbear/"
   	fi
	if [[ -z ${SSH_PASS_FILE} ]] || ! [[ -e ${SSH_PASS_FILE} ]] || [[ -z ${SSHPASS} ]]; then
		#shellcheck disable=SC2086
	   	${SUDO_USER} ssh ${BIND_INTERFACE_OPTION} ${IPV4} ${STRICT} "${TARGET}" "mkdir -p .ssh && echo '${PUBKEY}' >> .ssh/authorized_keys ${DROPBEAR_CMD}" || exit 1;
	else
		#shellcheck disable=SC2086
	   	${SUDO_USER} sshpass -f "${SSH_PASS_FILE}" ssh ${IPV4} ${BIND_INTERFACE_OPTION} ${STRICT} "${TARGET}" "mkdir -p .ssh && echo '${PUBKEY}' >> .ssh/authorized_keys ${DROPBEAR_CMD}" || exit 1;		
	fi
fi

#ssh-copy-id ${TARGET}  > /dev/null


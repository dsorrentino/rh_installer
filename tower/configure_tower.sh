#!/bin/bash

source settings/tower.environment
source functions.sh

for LOG_FILE in ${STDOUT} ${STDERR}
do
	cat /dev/null >${LOG_FILE}
done

PACKAGES=jq
LOG "stdout" "Installing pre-requisite packages: ${PACKAGES}"
PACKAGES=$(echo ${PACKAGES} | sed 's/,/ /g')
sudo yum install ${PACKAGES} -y >>${STDOUT} 2>>${STDERR}

RESULT=$(CREATE_CREDENTIAL "${TOWER_ORG}" "${CRED_GITHUB_NAME}" "${CRED_GITHUB_TYPE}" "${CRED_GITHUB_KEY}")

LOG "stdout" "Creating GITHUB credential."
if [[ ${RESULT} -ne 0 ]]
then
	LOG "stdout" "Failed to create GITHUB credentials."
	exit 1
fi

LOG "stdout" "Creating Director credential."
RESULT=$(CREATE_CREDENTIAL "${TOWER_ORG}" "${CRED_DIRECTOR_NAME}" "${CRED_DIRECTOR_TYPE}" "${CRED_DIRECTOR_USER}" "${CRED_DIRECTOR_PASSWORD}")

if [[ ${RESULT} -ne 0 ]]
then
	LOG "stdout" "Failed to create Director credentials."
	exit 1
fi

LOG "stdout" "Creating Project: ${PROJ_NAME}"
RESULT=$(CREATE_PROJECT "${TOWER_ORG}" "${PROJ_NAME}" "${PROJ_TYPE}" "${PROJ_DESCRIPTION}" "${CRED_GITHUB_NAME}" "${PROJ_URL}")
if [[ ${RESULT} -ne 0 ]]
then
	LOG "stdout" "Failed to create project: ${PROJ_NAME}"
	exit 1
fi

LOG "stdout" "Creating Inventory: ${INV_OPENSTACK_NAME}"
RESULT=$(CREATE_INVENTORY "${TOWER_ORG}" "${INV_OPENSTACK_NAME}" "${INV_OPENSTACK_VAR_FILE}")
if [[ ${RESULT} -ne 0 ]]
then
	LOG "stdout" "Failed to create inventory: '${INV_OPENSTACK_NAME}'"
	exit 1
fi

LOG "stdout" "Adding host '${HOST_DIRECTOR_NAME}' to inventory '${INV_OPENSTACK_NAME}'"
RESULT=$(ADD_HOST_TO_INVENTORY "${HOST_DIRECTOR_NAME}" "${INV_OPENSTACK_NAME}")
if [[ ${RESULT} -ne 0 ]]
then
	LOG "stdout" "Failed to add host '${HOST_DIRECTOR_NAME}' to '${INV_OPENSTACK_NAME}'"
	exit 1
fi

TEMPLATE_COUNT=$(echo "${!TEMPLATE[@]}" | wc -w)
KEY_COUNT=$(echo "${!TEMPLATE[@]}" | sed 's/[0-9],//g' | tr " " "\n" | sort -u | wc -l)
TEMPLATE_COUNT=$(( ${TEMPLATE_COUNT} / ${KEY_COUNT} ))

for NDX in $(seq 1 ${TEMPLATE_COUNT})
do
	for SETTING in $(echo "${!TEMPLATE[@]}" | sed 's/[0-9],//g' | tr " " "\n" | sort -u)
	do
	        VARNAME="TEMPLATE_${SETTING}"
	        eval ${VARNAME}="'${TEMPLATE[$NDX,$SETTING]}'"
	done
	LOG "stdout" "Creating template: ${TEMPLATE_Name}"
	RESULT=$(CREATE_TEMPLATE "${TEMPLATE_Name}" "${TEMPLATE_Description}" "${INV_OPENSTACK_NAME}" "${PROJ_NAME}" "${TEMPLATE_Credential}" "${TEMPLATE_Playbook}")
	if [[ ${RESULT} -ne 0 ]]
	then
		LOG "stdout" "Failed to create template: ${TEMPLATE_CONFIGURE_DIRECTOR_NAME}"
		exit 1
	fi
done

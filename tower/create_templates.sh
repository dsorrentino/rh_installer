#!/bin/bash

source settings/tower.environment
source functions.sh

for NDX in $(echo "${!TEMPLATE[@]}" | sed 's/,[a-zA-Z][a-zA-Z]*/ /g' |  xargs -n1 | sort -u)
do
	for SETTING in $(echo "${!TEMPLATE[@]}" | sed 's/[0-9],//g' | tr " " "\n" | sort -u)
	do
	        VARNAME="TEMPLATE_${SETTING}"
	        eval ${VARNAME}="'${TEMPLATE[$NDX,$SETTING]}'" 2>>${STDERR}
	done
	LOG "stdout" "Creating template: ${TEMPLATE_Name}"
	echo "Vars: ${TEMPLATE_Variables}"
	RESULT=$(CREATE_TEMPLATE "${TEMPLATE_Name}" "${TEMPLATE_Description}" "${INV_OPENSTACK_NAME}" "${HOST_DIRECTOR_NAME}" "${PROJ_NAME}" "${TEMPLATE_Credentials}" "${TEMPLATE_Playbook}" "${TEMPLATE_Variables}")
	if [[ ${RESULT} -ne 0 ]]
	then
		LOG "stdout" "Failed to create template: ${TEMPLATE_CONFIGURE_DIRECTOR_NAME}"
		exit 1
	fi
done

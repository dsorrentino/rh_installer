AWX="awx -k"
export TOWER_HOST=${TOWER_URL}

$(TOWER_USERNAME=${TOWER_USERNAME} TOWER_PASSWORD=${TOWER_PASSWORD} ${AWX} login -f human)

function CREATE_CREDENTIAL {
	local TOWER_ORG=$1
	local CRED_NAME=$2
	local CRED_TYPE=$3
	local CRED_USER=""
	local CRED_PASSWORD=""
	local CRED_KEY=""
	local RESULT=0

	case ${CRED_TYPE} in
		"Machine")
			CRED_USER=$4
			CRED_PASSWORD=$5
			;;
		"Source Control")
			CRED_KEY=$4
			;;
	esac

	if [[ $(RESOURCE_EXISTS "Credential" "${CRED_NAME}") == true ]]
	then
		LOG "file" "Credential with name '${CRED_NAME}' already exists."
	else
		CRED_TYPE_NUM=$(GET_ID "Credential Type" "${CRED_TYPE}")
		case ${CRED_TYPE} in
			"Machine")
				${AWX} -v credentials create --credential_type ${CRED_TYPE_NUM} \
					--name "${CRED_NAME}" \
					--organization "${TOWER_ORG}" \
					--inputs "{'username': '${CRED_USER}', 'password': '${CRED_PASSWORD}'}" >>${STDOUT} 2>>${STDERR}
				;;
			"Source Control")
				${AWX} -v credentials create --credential_type ${CRED_TYPE_NUM} \
					--name "${CRED_NAME}" \
					--organization "${TOWER_ORG}" \
					--inputs "{'ssh_key_data': '@${CRED_KEY}'}" >>${STDOUT} 2>>${STDERR}
				RESULT=$?
				;;
		esac
	fi
	echo ${RESULT}
}

function CREATE_INVENTORY {
	local TOWER_ORG=$1
	local INV_NAME=$2
	local INV_VARIABLE_FILE=$3
	local INV_ID=""
	local RESULT=0
	if [[ $(RESOURCE_EXISTS "Inventory" "${INV_NAME}") == true ]]
	then
		LOG "file" "Inventory already exists: ${INV_NAME}"
		if [[ ! -z "${INV_VARIABLE_FILE}" ]]
		then
			INV_ID=$(GET_ID "Inventory" "${INV_NAME}")
			if [[ -z "$(${AWX} inventory get ${INV_ID} 2>>${STDERR} | jq .variables 2>>${STDERR} | egrep 'osp_version' 2>>${STDERR})" ]]
			then
				LOG "file" "Inventory (ID: ${INV_ID}) is missing the variables. Adding them."
				${AWX} inventory modify ${INV_ID} --variables "@${INV_VARIABLE_FILE}" >>${STDOUT} 2>>${STDERR}
				RESULT=$?
			fi
		fi



	else
		if [[ -z "${INV_VARIABLE_FILE}" ]]
		then
			${AWX} inventory create --name ${INV_NAME} --organization "${TOWER_ORG}" >>${STDOUT} 2>>${STDERR}
			RESULT=$?
		else
			${AWX} inventory create --name ${INV_NAME} --organization "${TOWER_ORG}" --variables "@${INV_VARIABLE_FILE}" >>${STDOUT} 2>>${STDERR}
			RESULT=$?
		fi
	fi
	echo ${RESULT}
}

function ADD_HOST_TO_INVENTORY {
	local HOST_NAME=$1
	local INV_NAME=$2
	local INV_ID=''
	local RESULT=0
	if [[ $(RESOURCE_EXISTS "Host" "${HOST_NAME}") == true ]]
	then
		LOG "file" "Host '${HOST_NAME}' already exists."
	else
		INV_ID=$(GET_ID "Inventory" "${INV_NAME}")
		if [[ ! -z "${INV_ID}" ]]
		then
			${AWX} hosts create --name "${HOST_NAME}" --inventory ${INV_ID} >>${STDOUT} 2>>${STDERR}
			RESULT=$?
		else
			LOG "file" "Inventory not found: ${INV_NAME}"
			RESULT=1
		fi
	fi
	echo ${RESULT}
}

function LOG {
        local LOG_DIRECTION=$1
        local MSG=$2
        if [[ "${LOG_DIRECTION}" == "stdout" ]]
	then
		echo "[$(date)] $2" | tee -a ${STDOUT}
	elif [[ "${LOG_DIRECTION}" == "file" ]]
	then
		echo "[$(date)] $2" >> ${STDOUT}
	fi
}

function CREATE_PROJECT {
	local TOWER_ORG=$1
	local PROJ_NAME=$2
	local PROJ_TYPE=$3
	local PROJ_DESC=$4
	local PROJ_CREDS=""
	local PROJ_CRED_ID=""
	local PROJ_URL=""
	local PROJ_PLAYBOOK_DIR=""
	local RESULT=0
	case ${PROJ_TYPE} in
		"Git")
			PROJ_CREDS=$5
			PROJ_URL=$6
			PROJ_TYPE="git"
			;;
		"Manual")
			PROJ_PLAYBOOK_DIR=$5
			PROJ_TYPE=''
			;;
	esac

	if [[ $(RESOURCE_EXISTS "Project" "${PROJ_NAME}") == true ]]
	then
		LOG "file" "Project ${PROJ_Name} already exists."
	else
		PROJ_CRED_ID=$(GET_ID "Credential" "${PROJ_CREDS}")
		ORG_ID=$(GET_ID "Organization" "${TOWER_ORG}")
		${AWX} projects create --name "${PROJ_NAME}" --description "${PROJ_DESCRIPTION}" --scm_type "${PROJ_TYPE}" --scm_url "${PROJ_URL}" --scm_branch "master" --credential "${PROJ_CRED_ID}" --organization "${ORG_ID}" >>${STDOUT} 2>>${STDERR}
		RESULT=$?
	fi
	echo ${RESULT}
}

function RESOURCE_EXISTS {
	local RESOURCE_TYPE=$1
	local RESOURCE_NAME=$2
	local SEARCH_RESULT=""
	case ${RESOURCE_TYPE} in
		"Credential")
			SEARCH_RESULT=$(${AWX} credentials list 2>>${STDERR} | jq .results[].name  2>>${STDERR} | egrep "${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Inventory")
			SEARCH_RESULT=$(${AWX} inventory list 2>>${STDERR} | jq .results[].name  2>>${STDERR} | egrep "${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Host")
			SEARCH_RESULT=$(${AWX} hosts list --name "${RESOURCE_NAME}" 2>>${STDERR} | jq .count 2>>${STDERR} | egrep -v '^0$' 2>>${STDERR})
			;;
		"Project")
			SEARCH_RESULT=$(${AWX} projects list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep "${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Template")
			SEARCH_RESULT=$(${AWX} job_templates list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep "${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
	esac
	if [[ -z "${SEARCH_RESULT}" ]]
	then
		echo false
	else
		echo true
	fi
}

function GET_ID {
	local RESOURCE_TYPE=$1
	local RESOURCE_NAME=$2
	local SEARCH_RESULT=""
	case ${RESOURCE_TYPE} in
		"Credential")
			SEARCH_RESULT=$(${AWX} credentials list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep " ${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Credential Type")
			SEARCH_RESULT=$(${AWX} credential_type list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep " ${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Inventory")
			SEARCH_RESULT=$(${AWX} inventory list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep " ${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Project")
			SEARCH_RESULT=$(${AWX} projects list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep " ${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Organization")
			SEARCH_RESULT=$(${AWX} organization list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep " ${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
		"Template")
			SEARCH_RESULT=$(${AWX} job_templates list 2>>${STDERR} | jq '.results[] | "\(.id) \(.name)"' 2>>${STDERR} | egrep " ${RESOURCE_NAME}\"\$" 2>>${STDERR})
			;;
	esac
	if [[ ! -z "${SEARCH_RESULT}" ]]
	then
		SEARCH_RESULT=$(echo "${SEARCH_RESULT}" 2>>${STDERR} | awk '{print $1}' 2>>${STDERR} | sed 's/"//g' 2>>${STDERR})
	fi
	echo ${SEARCH_RESULT}
}

function CREATE_TEMPLATE {
	local NAME=$1
	local DESCRIPTION=$2
	local INVENTORY=$3
	local INV_ID=""
	local LIMIT_HOST=$4
	local PROJECT=$5
	local PROJ_ID=""
	local CREDENTIAL=$6
	local CRED_ID=""
	local PLAYBOOK=$7
	local VARIABLES=$8
	local TEMPLATE_ID=""
	local EXTRA_VARS_FILE=""
	local RESULT=0
	if [[ $(RESOURCE_EXISTS "Template" "${NAME}") == true ]]
	then
		LOG "file" "Template already exists: ${NAME}"
	else
		INV_ID=$(GET_ID "Inventory" "${INVENTORY}")
		PROJ_ID=$(GET_ID "Project" "${PROJECT}")
		CRED_ID=$(GET_ID "Credential" "${CREDENTIAL}")
		if [[ -z "${INV_ID}" || -z "${PROJ_ID}" || -z "${CRED_ID}" ]]
		then
			LOG "file" "Can't locate requested resources."
			LOG "file" "Inventory: ${INVENTORY} (${INV_ID})"
			LOG "file" "Project: ${PROJECT} (${PROJ_ID})"
			LOG "file" "Credential: ${CREDENTIAL} (${CRED_ID})"
			RESULT=1
		else
			if [[ ! -z "$VARIABLES" ]]
			then
				EXTRA_VARS_FILE=$(mktemp --suffix=create_template.yml)
				echo "${VARIABLES}" | sed "s/ None/ ''/g" >${EXTRA_VARS_FILE}
				VARIABLES="--extra_vars @${EXTRA_VARS_FILE} --ask_variables_on_launch true"
			fi
			if [[ ! -z "${LIMIT_HOST}" ]]
			then
				LIMIT_HOST="--limit ${LIMIT_HOST}"
			fi
			LOG "file" "${AWX} job_template create --name \"${NAME}\" --project \"${PROJ_ID}\" --playbook \"${PLAYBOOK}\" --description \"${DESCRIPTION}\" --inventory \"${INV_ID}\" ${VARIABLES}"
			${AWX} job_template create --name "${NAME}" --project "${PROJ_ID}" --playbook "${PLAYBOOK}" --description "${DESCRIPTION}" --inventory "${INV_ID}" ${LIMIT_HOST} ${VARIABLES} >>${STDOUT} 2>>${STDERR}
			RESULT=$?
			if [[ ${RESULT} -eq 0 ]]
			then
				TEMPLATE_ID=$(GET_ID "Template" "${NAME}")
				${AWX} job_templates associate --credential ${CRED_ID} ${TEMPLATE_ID} >>${STDOUT} 2>>${STDERR}
				RESULT=$?
			fi
			if [[ -f ${EXTRA_VARS_FILE} ]]
			then
				rm ${EXTRA_VARS_FILE}
			fi
		fi
	fi
	echo ${RESULT}

}

function TEST {
	local CRED_TYPE=$1
	local CRED_NAME=$2
	local CRED_USER=""
	local CRED_PASS=""
	local CRED_KEY=""
	echo "${CRED_TYPE}-${CRED_NAME}-${CRED_USER}-${CRED_PASS}-${CRED_KEY}"
}

function JOB_STATUS {
	local NAME=$1
	local TYPE=$2
	local JOB_STATUS=$(${AWX} unified_jobs list 2>>${STDERR} | jq '.results[] | "\(.type) \(.name) \(.status)"' 2>>${STDERR} | egrep "${NAME}" 2>>${STDERR} | egrep "${TYPE}" 2>>${STDERR} | sed "s/${NAME}//g;s/${TYPE}//g;s/ //g;s/\"//g" 2>>${STDERR})
	echo ${JOB_STATUS}
}

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


LOG "stdout" "Disabling Job Isolation"
LOG "stdout" "We need to do this since the Github Templates need to use some"
LOG "stdout" "locally created files that will contain information relaitive to"
LOG "stdout" "your enterprise/environment, such as your RHN connection data."

TOWER_CONFIG "AWX_PROOT_ENABLED" "false"

LOG "stdout" "Creating GITHUB credential."
RESULT=$(CREATE_CREDENTIAL "${TOWER_ORG}" "${CRED_GITHUB_NAME}" "${CRED_GITHUB_TYPE}" "Key" "${CRED_GITHUB_KEY}")
if [[ ${RESULT} -ne 0 ]]
then
	LOG "stdout" "Failed to create GITHUB credentials."
	exit 1
fi

if [[ ! -z "${CRED_DIRECTOR_KEY}" ]]
then
	LOG "stdout" "Creating Director credential using SSH Key ${CRED_DIRECTOR_KEY} file."
	RESULT=$(CREATE_CREDENTIAL "${TOWER_ORG}" "${CRED_DIRECTOR_NAME}" "${CRED_DIRECTOR_TYPE}" "Key" "${CRED_DIRECTOR_KEY}" "${CRED_DIRECTOR_USER}")
elif [[ ! -z "${CRED_DIRECTOR_PASSWORD}" ]]
then
	LOG "stdout" "Creating Director credential using password."
	RESULT=$(CREATE_CREDENTIAL "${TOWER_ORG}" "${CRED_DIRECTOR_NAME}" "${CRED_DIRECTOR_TYPE}" "Password" "${CRED_DIRECTOR_PASSWORD}" "${CRED_DIRECTOR_USER}")
else
	LOG "stdout" "Warning: No password or key provided for the Director Credential. Please create this manually."
fi

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

LOG "stdout" "Ensuring the Project is synchronized before continuing."

while [[ $(JOB_STATUS "${PROJ_NAME}" "project_update") == "running" ]]
do
	LOG "stdout" "Project is still updating."
	sleep 10
done


echo ""
echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
echo ""
echo "The different products in this project will need to register to RHN to install"
echo "necessary software. You will now be prompted for credential and pool information."
echo "The current iteration of this project will use a single RHN user/password"
echo "for registering a node to RHN. It will support using a differer Pool ID"
echo "for each product."
echo ""
echo "The encrypted files can be found in:"
echo "  ${RH_INSTALL_LOCAL_DIR}"
echo ""
echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
echo ""

RH_INSTALL_LOCAL_DIR=/var/lib/awx/projects/rh_installer.local
RHN_USER=""
RHN_PASSWORD=""
RHEL_POOL=""
REGISTRY_USER=""
REGISTRY_PASSWORD=""
REGISTRY_HOSTNAME="registry.redhat.io"

# Product RHN Pools
OPENSTACK_POOL=""
SATELLITE_POOL=""
RHV_POOL=""
OPENSHIFT_POOL=""

VAULT_PW_FILE=$(mktemp -p ~)

chmod 600 ${VAULT_PW_FILE}
if [[ -z "$(sudo ls ${RH_INSTALL_LOCAL_DIR}/vault_rhn_pw.txt 2>/dev/null)" ]]
then
	head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20  >${VAULT_PW_FILE}
else
	sudo cat ${RH_INSTALL_LOCAL_DIR}/vault_rhn_pw.txt >${VAULT_PW_FILE}
	if [[ ! -z "$(sudo ls ${RH_INSTALL_LOCAL_DIR}/config.yml 2>/dev/null)" ]]
	then
		sudo cat ${RH_INSTALL_LOCAL_DIR}/config.yml >${VAULT_PW_FILE}.config.yml
	fi

	if [[ -f ${VAULT_PW_FILE}.config.yml ]]
	then
		RHN_USER=$(ansible -m include_vars -a ${VAULT_PW_FILE}.config.yml localhost | sed 's/localhost | SUCCESS => //g' | jq .ansible_facts.rhn_user | sed 's/"//g')
		RHEL_POOL=$(ansible -m include_vars -a ${VAULT_PW_FILE}.config.yml localhost | sed 's/localhost | SUCCESS => //g' | jq .ansible_facts.rhel_pool.__ansible_vault | sed 's/"//g;s/\\n/\n/g' | ansible-vault decrypt --vault-password-file ${VAULT_PW_FILE} 2>/dev/null)
		OPENSTACK_POOL=$(ansible -m include_vars -a ${VAULT_PW_FILE}.config.yml localhost | sed 's/localhost | SUCCESS => //g' | jq .ansible_facts.openstack_pool.__ansible_vault | sed 's/"//g;s/\\n/\n/g' | ansible-vault decrypt --vault-password-file ${VAULT_PW_FILE} 2>/dev/null)
		REGISTRY_USER=$(ansible -m include_vars -a ${VAULT_PW_FILE}.config.yml localhost | sed 's/localhost | SUCCESS => //g' | jq .ansible_facts.registry_user | sed 's/"//g')
	fi
fi

USER_INPUT=""
while [[ -z "${USER_INPUT}" ]]
do
	read -p "[RHN] Enter username to login to RHN Portal with [${RHN_USER}]: " USER_INPUT
	if [[ -z "${USER_INPUT}" ]]
	then
		USER_INPUT=${RHN_USER}
	fi
done
RHN_USER=${USER_INPUT}


while [[ -z "${RHN_PASSWORD}" ]]
do
        read -s -p "[RHN] Enter RHN Portal password for ${RHN_USER}: " RHN_PASSWORD1
        echo ""
        read -s -p "[RHN] Confirm RHN Portal password for ${RHN_USER}: " RHN_PASSWORD2
        echo ""
	if [[ ! -z "${RHN_PASSWORD1}" ]]
	then
        	if [[ "${RHN_PASSWORD1}" == "${RHN_PASSWORD2}" ]]
        	then
                	RHN_PASSWORD=${RHN_PASSWORD1}
        	else
                	echo "[Error] Passwords did not match."
        	fi
	else
               	echo "[Error] Password can not be empty."
	fi
done

USER_INPUT=""
while [[ -z "${USER_INPUT}" ]]
do
	read -p "[RHEL] Enter RHN Pool for RHEL [${RHEL_POOL}]: " USER_INPUT
	if [[ -z "${USER_INPUT}" ]]
	then
		USER_INPUT=${RHEL_POOL}
	fi
done
RHEL_POOL=${USER_INPUT}

USER_INPUT=""
read -p "[Openstack] Enter RHN Pool for Openstack [${OPENSTACK_POOL}]: " USER_INPUT
if [[ -z "${USER_INPUT}" ]]
then
	USER_INPUT=${OPENSTACK_POOL}
fi
OPENSTACK_POOL=${USER_INPUT}

if [[ -z "${OPENSTACK_POOL}" ]]
then
	LOG "stdout" "No Openstack pool provided, defaulting to RHEL Pool."
	OPENSTACK_POOL=${RHEL_POOL}
fi

echo ""
echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
echo ""
echo "Openstack versions 15+ require access to redhat.registry.io when"
echo "pulling containers for the Undercloud and Overcloud. You can use"
echo "your portal credentials to pull this data, however, it's not recommended"
echo "as this information needs to be written to a YAML file as part of the"
echo "installation procedure."
echo ""
echo "You can create registry only credentials by logging into the RHN Portal"
echo "and visiting the following URL:"
echo ""
echo "https://access.redhat.com/terms-based-registry/"
echo ""
echo "You will next be prompted asking for these credentials. If you leave"
echo "them blank, your RHN Portal credentials will be used instead. If you"
echo "intend to create them later, enter false information into these prompts"
echo "now and you can always update the data later in this file:"
echo ""
echo "  ${RH_INSTALL_LOCAL_DIR}"
echo ""
echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"

USER_INPUT=""
read -p "[Openstack] Enter Registry User for ${REGISTRY_HOSTNAME} [${REGISTRY_USER}]: " USER_INPUT
if [[ -z "${USER_INPUT}" ]]
then
	USER_INPUT=${REGISTRY_USER}
fi

if [[ -z "${REGISTRY_USER}" ]]
then
	REGISTRY_USER=${RHN_USER}
fi

USER_INPUT=""
read -p "[Openstack] Enter Registry User Password for ${REGISTRY_HOSTNAME} [${REGISTRY_PASSWORD}]: " USER_INPUT
if [[ -z "${USER_INPUT}" ]]
then
	USER_INPUT=${REGISTRY_PASSWORD}
fi

if [[ -z "${REGISTRY_PASSWORD}" ]]
then
	REGISTRY_USER=${RHN_PASSWORD}
fi

sudo mkdir -p ${RH_INSTALL_LOCAL_DIR}
sudo chown -R awx:awx ${RH_INSTALL_LOCAL_DIR}

LOG "stdout" "Creating Vault credential."
RESULT=$(CREATE_CREDENTIAL "${TOWER_ORG}" "${CRED_RH_INSTALLER_VAULT_NAME}" "Vault" "Password" "$(cat ${VAULT_PW_FILE})")

LOG "stdout" "Storing encrypted data in ${RH_INSTALL_LOCAL_DIR}/config.yml"
echo ""
echo "rhn_user: ${RHN_USER}" | sudo tee ${RH_INSTALL_LOCAL_DIR}/config.yml
echo -n "${RHN_PASSWORD}" | ansible-vault encrypt_string --vault-password-file ${VAULT_PW_FILE} --stdin-name 'rhn_password' | sudo tee -a ${RH_INSTALL_LOCAL_DIR}/config.yml
echo -n "${RHEL_POOL}" | ansible-vault encrypt_string --vault-password-file ${VAULT_PW_FILE} --stdin-name 'rhel_pool' | sudo tee -a ${RH_INSTALL_LOCAL_DIR}/config.yml
echo -n "${OPENSTACK_POOL}" | ansible-vault encrypt_string --vault-password-file ${VAULT_PW_FILE} --stdin-name 'openstack_pool' | sudo tee -a ${RH_INSTALL_LOCAL_DIR}/config.yml
echo "registry_hostname: ${REGISTRY_HOSTNAME}" | sudo tee -a ${RH_INSTALL_LOCAL_DIR}/config.yml
echo "registry_user: ${REGISTRY_USER}" | sudo tee -a ${RH_INSTALL_LOCAL_DIR}/config.yml
echo -n "${REGISTRY_PASSWORD}" | ansible-vault encrypt_string --vault-password-file ${VAULT_PW_FILE} --stdin-name 'registry_password' | sudo tee -a ${RH_INSTALL_LOCAL_DIR}/config.yml

sudo mv ${VAULT_PW_FILE} ${RH_INSTALL_LOCAL_DIR}/vault_rhn_pw.txt
sudo chmod 0600 ${RH_INSTALL_LOCAL_DIR}/vault_rhn_pw.txt
sudo chown -R awx:awx ${RH_INSTALL_LOCAL_DIR}

for NDX in $(echo "${!TEMPLATE[@]}" | sed 's/,[a-zA-Z][a-zA-Z]*/ /g' |  xargs -n1 | sort -u)
do
	for SETTING in $(echo "${!TEMPLATE[@]}" | sed 's/[0-9],//g' | tr " " "\n" | sort -u)
	do
	        VARNAME="TEMPLATE_${SETTING}"
	        eval ${VARNAME}="'${TEMPLATE[$NDX,$SETTING]}'" 2>>${STDERR}
	done
	LOG "stdout" "Creating template: ${TEMPLATE_Name}"
	RESULT=$(CREATE_TEMPLATE "${TEMPLATE_Name}" "${TEMPLATE_Description}" "${INV_OPENSTACK_NAME}" "${HOST_DIRECTOR_NAME}" "${PROJ_NAME}" "${TEMPLATE_Credentials}" "${TEMPLATE_Playbook}" "${TEMPLATE_Variables}")
	if [[ ${RESULT} -ne 0 ]]
	then
		LOG "stdout" "Failed to create template: ${TEMPLATE_CONFIGURE_DIRECTOR_NAME}"
		exit 1
	fi
done

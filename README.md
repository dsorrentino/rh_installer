# rh_installer
Project Name: rh_installer
Project Description: The goal of this project is to create a simplified process to 
                     deploy Red Hat Products from using a base installatin of Ansible Tower.

How to use:

1) Create a RHEL VM/Node and install Ansible Tower on it.
   Pre-requisites:
     This node must be able to reach the internet so it can configure and pull
     from this git repository.
2) Clone this repository to the VM/Node.
3) In the cloned respository, edit the following file:
     rh_installer/tower/settings/tower.environment
   This contains variables to configure various artifacts in Ansible Tower (See Below)

   Additionally, you can edit the files for the products products
   located in this directory:
     rh_installer/tower/settings/inventories/

   These are just the default settings, you can always update the product settings in
   the inventory within Tower after you've done step 4.

4) Run the script: rh_installer/tower/configure_tower.sh

This script will create a number of artifacts in your Ansible Tower Deployment:
- Templates:
    There will be a number of templates to execute various installation procedure.
    These will be detailed further down in this README file.
- Credentials:
    Credentials for the Github repository and the Director node will be created.
- Projects:
    A project called 'RH Installer' will be created and configured to point to this repository.
- Inventories:
    There will be an inventory created for each of the different Red Hat Products. The first
    product we will be working on is Red Hat Openstack.  Each inventory will have a number 
    of variables created at the inventory level that will be used as part of the deployment process.

#################
#   Templates   #
#################
Each set of templates is oriented toward setting up a particular Red Hat Product.  We will
organize them as such below to the corresponding Product/Inventory:


Product:  Red Hat Openstack
Inventory: Openstack
Description: Please carefully review all of the Inventory level variables before executing any
             of the associated playbooks. Due to the complextity and configurability of Red Hat
             Openstack, there's alot of variables to consider.

Name: Configure Director Node
Pre-requisites: You have a RHEL 7/8 Node that you will be using for Director.
          NOTE: Only Red Hat Openstack 15+ is supported on RHEL 8.
Description: This will Register the node to RHN, configure repositories, install the Triple-O 
             packages, install the director overcloud packages and perform a yum update
             on the node.  You should reboot the node at the completion of executing this playbook.

Name: Configure Triple-O Director
Pre-requisites: You have a RHEL 7/8 Node installed and configured for the appropriate repositories and
                the appropriate Triple-O packages have been installed.
Description: This will create the stack user and configure Triple-O to perform the installation
             of your undercloud.

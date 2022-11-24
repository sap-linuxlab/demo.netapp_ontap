# Table of Contents

[Table of Contents](#Table-of-Contents)

[Table of Figures](#Table-of-Figures)

[Table of Tables](#Table-of-Tables)

[Version History](#Version-History)

[Introduction](#Introduction)

[Target audience and document goal](#Target-audience-and-document-goal)

[Getting started](#Getting-started)

[Prepare the environment](#Prepare-the-environment)

[Prepare Ubuntu system](#Prepare-Ubuntu-system)

[Add Ansible APT repository](#Add-Ansible-APT-repository)

[Install Ansible](#Install-Ansible)

[Verify collections and if necessary, upgrade netapp.ontap collection](#Verify-collections-and-if-necessary,-upgrade-netapp.ontap-collection)

[Install ZAPI Libs for Python](#Install-ZAPI-Libs-for-Python)

[Prepare ONTAP](#Prepare-ONTAP)

[Create self-signed certificate on the Linux server on which you run the Ansible playbooks](#Create-self-signed-certificate-on-the-Linux-server-on-which-you-run-the-Ansible-playbooks)

[Add certificates to ONTAP and configure users and passwords](#Add-certificates-to-ONTAP-and-configure-users-and-passwords)

[Workflows](#Workflows)

[Day 1](#Day-1)

[Daily operation](#Daily-operation)

[Day 2](#Day-2)

[Cleanup](#Cleanup)

[Querying ONTAP information using Playbooks](#Querying-ONTAP-information-using-Playbooks)

[Running Playbooks](#Running-Playbooks)

[YAML Files](#YAML-Files)

[inventory.yml 15](#_Toc120111140)

[ontap\_vars.yml 16](#_Toc120111141)

[system\_details.yml (ZAPI API and native CLI command) 16](#_Toc120111142)

[get\_svms.yml (REST API) 17](#_Toc120111143)

[create\_svm.yml 18](#_Toc120111144)

[set\_svm\_options.yml 19](#_Toc120111145)

[create\_export\_policy.yml 20](#_Toc120111146)

[create\_volume.yml 20](#_Toc120111147)

[create\_snapshot.yml 21](#_Toc120111148)

[restore\_snapshot.yml 22](#_Toc120111149)

[create\_clone.yml 23](#_Toc120111150)

[delete\_clone.yml 24](#_Toc120111151)

[delete\_snapshot.yml 24](#_Toc120111152)

[delete\_volume.yml 25](#_Toc120111153)

[delete\_svm.yml 26](#_Toc120111154)

[References 26](#_Toc120111155)

# Table of Figures

[Figure 1: Current collection version from netapp.ontap](#Figure-1:-Current-collection-version-from-netapp.ontap)

[Figure 2: Workflow Day 1 automation](#Day-1)

[Figure 3: Workflow for daily operation](#Daily-operation)

[Figure 4: Workflow Day 2 automation](#Day-2)

# Table of Tables

[Table 1: Version history](#Version-history)

# Version History

| Date | Version | Comment |
| --- | --- | --- |
| 30.08.2022 | 0.1 | Initial Version |
| 31.08.2022 | 0.2 | Implemented changes proposed from Elmar |
| 24.10.2022 | 0.3 | Implemented suggestions from RH and answered open questions |
| 22.11.2022 | 0.4 | Changes according to remarks of NetApp colleagues |

_Table 1: Version history_

# Introduction

This document describes how to execute Ansible Playbooks against NetApp ONTAP systems.

## Target audience and document goal

the document is intended to give SAP administrators an introduction to the Ansible automation of recurring administrative activities.

- This document includes
  - Brief description how to automate tasks on NetApp ONTAP systems
  - Example configuration of Ansible on a Ubuntu 20.04 server
 Instead of Ubuntu 20.094 any other OS can be used which supports Ansible and of course also systems which provide a complete Ansible orchestration like RedHat Ansible Automation Platform
  - Example Playbooks
- This document does not include
  - Any storage architecture related topics
  - Security related topics
 i.e. encrypting passwords

## Getting started

This document has been written to demonstrate automating tasks using Ansible for NetApp ONTAP based systems. More details can be found in this documentation: [https://netapp.io/2018/10/08/getting-started-with-netapp-and-ansible-install-ansible/](https://netapp.io/2018/10/08/getting-started-with-netapp-and-ansible-install-ansible/)

This document can therefore be used for the following storage products:

- ONTAP (FAS/AFF)
- ONTAP Select
- Cloud Volumes ONTAP (CVO)
- Amazon FSx for NetApp ONTAP (FSxN)

To run Ansible Playbooks a prerequisite is a running Ansible version. There are a lot of tutorials how to install Ansible on MacOS, Linux, Windows are available on the internet. In our environment we decided to use Ubuntu as operating system and run Ansible. For completeness, we will also cover what needs to be configured on the Ubuntu system. This is described in the chapter [Prepare Ubuntu system](#_Prepare_Ubuntu_system). If Ansible should run on another operating system, Ansible and the operating system need to be prepared accordingly.

What needs to be configured on the ONTAP based system will be described in the chapter [Prepare ONTAP](#_Prepare_ONTAP).

First, it is important to mention, that there are 4 ways to interact with ONTAP based systems.

Two frontends:

1. Web based System Manager
2. SSH

And two API interfaces:

1. ZAPI
2. REST API

The Web based System Manager and SSH cannot be used with Ansible!

The remaining APIs are REST API and ZAPI API. The last ONTAP release supporting ZAPI API is ONTAP 9.12.1. The API which should therefore be used to be future ready is REST API. To make sure, the default API being used is the REST API, we include the parameter 'use\_rest: always' in all Playbooks. If you have a look into the "NetApp.Ontap – Ansible Documentation" at [https://docs.ansible.com/ansible/latest/collections/netapp/ontap/index.html](https://docs.ansible.com/ansible/latest/collections/netapp/ontap/index.html)you will recognize, that for each module certain parameters are documented. For some parameters it is explicitly mentioned that the parameter is only available using the REST API, for some parameters it is explicitly mentioned that the parameter ins only available using the ZAPI API. So usually, all other parameters are available for REST and ZAPI API.

There are four different scenarios depending on the API being used

1. We us a module and specify only parameters which are available using the REST API **and** ZAPI API. We **do not** specify any parameter which is exclusively available **only** with REST API or **only** with ZAPI API
 This results in using the REST API
2. We us a module and specify parameters which are available using the REST API **and** ZAPI API. We specify at least one parameter which is available **only** with REST API.
 This results in using the REST API
3. We us a module and specify parameters which are available using the REST API **and** ZAPI API. We specify at least one parameter available **only** with ZAPI API.
 This results in using the ZAPI API. If ZAPI API is being used, Ansible will print a warning like this: [WARNING]: Using ZAPI for na\_ontap\_command, ignoring 'use\_rest: always'.
4. We us a module and specify parameters which are available using the REST API and ZAPI API. We specify at least one parameter which is available **only** with ZAPI API **and** we specify at least one parameter which is available **only** with REST API.
 This results in an error, because for a module only REST API or ZAPI API can be used

These four scenarios are listed for completeness and to make sure, users understand what will happen if they specify certain parameters. NetApp is releasing subsequently new versions of the netapp.ontap collection and parameters which are available with ZAPI only, will be supported step be step with REST API.

Since we must use REST API or ZAPI API to execute commands via Ansible on ONTAP based systems, SSH cannot be used as authentication mechanism. There are two options to connect using REST API or ZAPI API

1. User/Password based authentication
2. Certificate based authentication

User/Password based authentication is not the preferred way, because no one wants to enter a password in plain text in a config file. Certificate authentication is the preferred way to go. How to set up certificate based authentication will be described in chapter [Prepare ONTAP](#_Prepare_ONTAP). Unfortunately, not all commands available via NetApp ONTAP command line are exposed through REST API and/or ZAPI API. ZAPI API offers a module to execute native ONTAP command line commands. When using this module, certificate authentication can not be used. Instead, user/password authentication must be used.

# Prepare the environment

In our environment we used an Ubuntu 20.04 system to run Ansible playbooks. This chapter describes what needs to be configured on the Ubuntu 20.04 system and on the NetApp ONTAP system to execute Ansible Playbooks. The basic requirements are:

1. Installed Ansible version
2. ontap collection
3. Necessary python dependencies

## Prepare Ubuntu system

The preparation of the Ubuntu system with regards to the requirements described above consists of the following steps

1. Install Ansible version
  1. [Add Ansible APT repository](#_Add_Ansible_APT)
  2. [Install Ansible](#_Install_Ansible)
2. ontap collection
  1. [Verify collections and if necessary, upgrade netapp.ontap collection](#_Verify_collections_and)
3. Necessary python dependencies
  1. [Install ZAPI Libs for Python](#_Install_ZAPI_Libs)

If you plan to run Ansible on a different operating system (i.e. MacOS), you have to implement the requirements accordingly.

### Add Ansible APT repository

For adding the Ansible APT repository, execute the following steps:

- holgerz@HOLGERZ02-PC:~/# mkdir ansible
- holgerz@HOLGERZ02-PC:~/# cd ansible
- holgerz@HOLGERZ02-PC:~/ansible# apt install software-properties-common
- holgerz@HOLGERZ02-PC:~/ansible# add-apt-repository --yes --update ppa:ansible/ansible

### Install Ansible

For installing Ansible, execute the following command:

- holgerz@HOLGERZ02-PC:~/ansible# apt install ansible

Verify successful installation by executing the following commands:

- holgerz@HOLGERZ02-PC:~/ansible# dpkg -l | grep ansible
 ii ansible 5.10.0-1ppa~focal all batteries-included package providing a curated set of Ansible collections in addition to ansible-core
 ii ansible-core 2.12.7-1ppa~focal all Ansible IT Automation
- holgerz@HOLGERZ02-PC:~/ansible# ansible –version
 ansible [core 2.12.8]
 config file = /etc/ansible/ansible.cfg
 configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
 ansible python module location = /usr/lib/python3/dist-packages/ansible
 ansible collection location = /root/.ansible/collections:/usr/share/ansible/collections
 executable location = /usr/bin/ansible
 python version = 3.8.10 (default, Jun 22 2022, 20:18:18) [GCC 9.4.0]
 jinja version = 2.10.1
 libyaml = True

### Verify collections and if necessary, upgrade netapp.ontap collection

Verify the actual version of the netapp.ontap collection as shown in Figure 1 at:

[https://docs.ansible.com/ansible/latest/collections/netapp/ontap/index.html](https://docs.ansible.com/ansible/latest/collections/netapp/ontap/index.html)

![](RackMultipart20221124-1-7e8pfc_html_2ff959e5c53868eb.png)

_Figure 1: Current collection version from netapp.ontap_

The current collection is version 21.22.0. Now let's verify which collection version is installed:

- holgerz@HOLGERZ02-PC:~/ansible# ansible-galaxy collection list | grep netapp
 # /usr/lib/python3/dist-packages/ansible\_collections
 Collection Version
 ----------------------------- -------
 netapp.aws 21.7.0
 netapp.azure 21.10.0
 netapp.cloudmanager 21.18.0
 netapp.elementsw 21.7.0
 netapp.ontap 21.20.0
 netapp.storagegrid 21.10.0
 netapp.um\_info 21.8.0
 netapp\_eseries.santricity 1.3.0

The default collection search path points to
/usr/lib/python3/dist-packages/ansible\_collections and netapp.ontap collection is version 21.20.0. Since this is not the current version, we need to upgrade to netapp.ontap version 21.22.0 and place the updated modules into the default collection search path. It is necessary to move the updated collections to the default search path since collections are installed as default in the home directory of the current user in ~/.ansible and if any other user wants to execute Ansible playbooks on the same server he either needs to download the updated collection again or he well us a version of netapp.ontap which is not up to date.

To update the netapp.ontap collection for all users, the following steps need to be executed:

1. Install current version
holgerz@HOLGERZ02-PC:~/ansible# ansible-galaxy collection install netapp.ontap
 Starting galaxy collection install process
 Process install dependency map
 Starting collection install process
 Downloading https://galaxy.ansible.com/download/netapp-ontap-21.22.0.tar.gz to /root/.ansible/tmp/ansible-local-107\_ro3sp\_1/tmp1mk2xjz8/netapp-ontap-21.22.0-85bxl69u
 Installing 'netapp.ontap:21.22.0' to '/root/.ansible/collections/ansible\_collections/netapp/ontap'
 netapp.ontap:21.22.0 was installed successfully
2. Remove netapp.ontap from default collection search path
holgerz@HOLGERZ02-PC:~/ansible# rm /usr/lib/python3/dist-packages/ansible\_collections/netapp/ontap
3. Move the newly installed netapp.ontap collection from /root/.ansible/collections/ansible\_collections/netapp/ontap into the default collection search path
holgerz@HOLGERZ02-PC:~/ansible# mv /root/.ansible/collections/ansible\_collections/netapp/ontap /usr/lib/python3/dist-packages/ansible\_collections/netapp/

### Install ZAPI Libs for Python

As mentioned in the Introduction, we can use the REST API or the ZAPI API when executing commands on the ONTAP system. For using the ZAPI API, there is the need to install the NetApp-Lib for Python. To achieve this, the following steps must be executed:

1. If necessary, install Python pip
holgerz@HOLGERZ02-PC:~/ansible# apt install python3-pip
2. Install NetApp ZAPI Python Libs
holgerz@HOLGERZ02-PC:~/ansible# pip install NetApp-Lib

## Prepare ONTAP

Now we must prepare ONTAP to be able to access the REST API and ZAPI API using certificate base authentication. In addition, we must configure ONATP to access the ZAPI API using user/password for executing native ONTAP based command line interface commands.

The following steps are necessary:

- [Create self-signed certificate on the Linux server on which you run the Ansible playbooks](#_Create_self-signed_certificate)
We will create a public key file and a private key file on the Linux server on which we plan to run the Ansible playbooks.
- [Add certificates to ONTAP and configure users and passwords](#_Add_certificates_to)
The public key file create in the step above will then be uploaded to the ONTAP system to allow authentication using the private key file, also created in the step above, to access the REST and/or ZAPI API.

### Create self-signed certificate on the Linux server on which you run the Ansible playbooks

When you create the self-signed certificate on the Linux server, it is important to enter the username in "Common Name" which you are going to configure in ONTAP in the steps described in chapter [Add certificates to ONTAP and configure users and passwords](#_Add_certificates_to)

- Create self-signed certificate
 The following command creates two files, ontap.key which is the private key and ontap.pem which is the public key:
holgerz@HOLGERZ02-PC:~/ansible# openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -keyout ontap.key -out ontap.pem
 Generating a RSA private key
 .....................+++++
 ....................................................+++++
 writing new private key to 'ontap.key'
 -----
 You are about to be asked to enter information that will be incorporated
 into your certificate request.
 What you are about to enter is what is called a Distinguished Name or a DN.
 There are quite a few fields but you can leave some blank
 For some fields there will be a default value,
 If you enter '.', the field will be left blank.
 -----
 Country Name (2 letter code) [AU]:DE
 State or Province Name (full name) [Some-State]:BW
 Locality Name (eg, city) []:Stuttgart
 Organization Name (eg, company) [Internet Widgits Pty Ltd]:NetApp
 Organizational Unit Name (eg, section) []:Testcenter
 Common Name (e.g. server FQDN or YOUR name) []:holger
 Email Address []:holger.zecha@netapp.com

### Add certificates to ONTAP and configure users and passwords

We must add the private key of the certificate to ONTAP system and configure the user(s) who are allowed to log on with the corresponding public key file of the certificate. Some legacy commands unfortunately have the requirement to authenticate through the ZAPI API to the console using user/password. For completeness we therefore will also configure user/password access to run console commands through ZAPI API.

- SSH to the cluster management IP of your ONTAP Cluster and login with a user who has admin permissions
holgerz@HOLGERZ02-PC:~/ansible# ssh [admin@192.168.71.25](mailto:admin@192.168.71.25)
 (admin@192.168.71.25) Password:
 Last login time: 9/12/2022 15:04:18
 testcl1::\>
- To install the public key file of your certificate execute the following command:
testcl1::\> security certificate install -type client-ca -vserver testcl1
\<\<
 Insert content of the public key file ontap.pem
 \>\>
You should keep a copy of the CA-signed digital certificate for future reference.
 The installed certificate's CA and serial number for reference:
 CA: holger
 serial: 5314F75B537821699ACB32C0CB85BBDC6EC3A472

 The certificate's generated name for reference: holger
- Create necessary user login information for REST API (application http) and ZAPI API (application ontapi) for certificate-based authentication
testcl1::\> security login create -user-or-group-name holger -application ontapi -authentication-method cert -vserver testcl1
 testcl1::\> security login create -user-or-group-name holger -application http -authentication-method cert -vserver testcl1
- Since we also need user/password-based authentication for the ZAPI API to excute native console commands, we configure this authentication method using the following command
testcl1::\> security login create -user-or-group-name holger -application ontapi -authentication-method password -vserver testcl1
- To execute console commands via ZAPI API we also must configure a user for console access with the following command
testcl1::\> security login create -user-or-group-name holger -application console -authentication-method password -vserver testcl1

# Workflows

Now that everything is prepared on the Linux server and inside ONTAP we can start to configure the necessary Ansible Playbooks

- [Day 1](#_Day_1) automation
- [Daily operation](#_Daily_operation)
- [Day 2](#_Day_2) automation
- In addition, we added Playbooks needed for [Cleanup](#_Cleanup)
- Querying ONTAP information is described in [Querying ONTAP information using Playbooks](#_Querying_ONTAP_information)

## Day 1

The necessary steps for Day 1 automation are visualized in Figure 2. The following Playbooks are needed:

- [create\_svm.yml](#_create_svm.yml)
 If necessary, create a new SVM which will be used for creating the needed volumes.
- [set\_svm\_options.yml](#_set_svm_options.yml)
 Set SVM options needed for optimal performance
- [create\_export\_policy.yml](#_create_export_policy.yml)
 If necessary, create a new export which will be assigned to the newly created volumes.
- [create\_volume.yml](#_create_volume.yml)
 Create new volumes
- [create\_snapshot.yml](#_create_snapshot.yml)
 Take a SnapShot from the newly created volumes

![](RackMultipart20221124-1-7e8pfc_html_be77a18189013a4a.png)

_Figure 2: Workflow Day 1 automation_

## Daily operation

The necessary steps for daily operation are visualized in Figure 3. The following Playbooks are needed:

- [restore\_snapshot.yml](#_restore_snapshot.yml)
 Restore a SnapShot

![](RackMultipart20221124-1-7e8pfc_html_7a65b2f345aab652.png)

_Figure 3: Workflow for daily operation_

## Day 2

For Day 2 automation we assume, that we need to do SAP system refreshes. The workflow for Day 2 automation is visualized in Figure 4. The following Playbooks are needed:

- [create\_snapshot.yml](#_create_snapshot.yml)
 If necessary, create a SnapShot
- [create\_clone.yml](#_create_clone.yml)
 Create FelxClone

![](RackMultipart20221124-1-7e8pfc_html_9767b945efa74671.png)

_Figure 4: Workflow Day 2 automation_

## Cleanup

To clean up everything i.e., deleting a FlexClone before creating a new FlexClone the following Playbooks are needed:

- [delete\_clone.yml](#_delete_clone.yml)
 Delete existing FlexClone
- [delete\_snapshot.yml](#_delete_snapshot.yml)
 Delete existing SnapShot
- [delete\_volume.yml](#_delete_volume.yml)
 Delete existing Volume
- [delete\_svm.yml](#_delete_svm.yml)
 Delete Storage Virtual Machine

## Querying ONTAP information using Playbooks

As mentioned before, there are two ways of querying ONTAP details.

- Running native CLI commands using ZAPI API
[system\_details.yml (ZAPI API and native CLI command)](#_system_details.yml_(ZAPI_API)
- Querying predefined information using REST API.
[get\_svms.yml (REST API)](#_get_svms.yml_(REST_API))

If information is needed which is not accessible via REST AP, ZAPI API must be used. Examples are documented in the two YAML files mentioned above.

# Running Playbooks

There are three ways when running Playbooks

1. Code all parameters inside the Playbook

- Use an inventory defined in an inventory file. To run a Playbook using an inventory defined in inventory.yml execute
ansible-playbook -i inventory.yml create\_svm.yml
- Use variables defined in a variable file. To run the Playbook Playbook using an inventory defined in ontap\_vars.yml execute
ansible-playbook create\_svm.yml --extra-vars "@ontap\_vars.yml"

An example inventory file is shown in chapter [inventory.yml](#_inventory.yml).

An example variable file is shown in chapter [ontap\_vars.yml](#_ontap_vars.yml).

The key value pairs are self-explaining and fit parameters which are described for each netapp.ontap Ansible module. The subsequent Playbooks make use of the defined variables either from [inventory.yml](#_inventory.yml) or from [ontap\_vars.yml](#_ontap_vars.yml)

# YAML Files

Here are all needed YAML files.

## inventory.yml

ontapservers:

hosts:

testcl1-01:

hostname: 192.168.71.25 or ansible\_host (use inventory\_hostname then in playbook)

ansible\_host: 192.168.71.25

username: "holger"

password: "your password"

keyfile: "/root/ansible/certs/ontap.key"

certfile: "/root/ansible/certs/ontap.pem"

svmname: "svm-sap03"

aggrlist: "data\_aggr\_0"

exportpolicyname: "192er\_LAN\_SAP"

sizeunit: "gb"

datavolumesize: "100"

datavolumename: "L01\_data"

logvolumename: "L01\_log"

logvolumesize: "256"

sharedvolumename: "L01\_shared"

sharedvolumesize: "256"

dataaggrname: "data\_aggr\_0"

protocols: "nfs,nfs3"

networkrange: "192.168.71.0/24"

ruleindex: "100"

rorule: "none"

rwrule: "any"

snapshotpostfix: "\_snap\_1"

clonepostfix: "\_clone\_1"

linuxservers:

hosts:

velociraptor:

ansible\_host: 192.168.71.229

ansible\_ssh\_user: holger

ansible\_password: \<your password\>

## ontap\_vars.yml

hostname: "192.168.71.25"

username: "holger"

password: "your password"

keyfile: "/root/ansible/certs/ontap.key"

certfile: "/root/ansible/certs/ontap.pem"

svmname: "svm-sap03"

aggrlist: "data\_aggr\_0"

exportpolicyname: "192er\_LAN\_SAP"

sizeunit: "gb"

datavolumesize: "100"

datavolumename: "L01\_data"

logvolumename: "L01\_log"

logvolumesize: "256"

sharedvolumename: "L01\_shared"

sharedvolumesize: "256"

dataaggrname: "data\_aggr\_0"

protocols: "nfs,nfs3"

networkrange: "192.168.71.0/24"

ruleindex: "100"

rorule: "none"

rwrule: "any"

snapshotpostfix: "\_snap\_1"

clonepostfix: "\_clone\_1"

## system\_details.yml (ZAPI API and native CLI command)

---

- name: Get System details 1

connection: local

collections:

- netapp.ontap

hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

tasks:

- name: Get details of installed cluster

na\_ontap\_command:

use\_rest: always

hostname: "{{ (inventory\_)hostname }}"

username: "{{ username }}"

password: "{{ password }}"

https: true

validate\_certs: false

command: ['system show -instance']

register: ontap\_return

- debug: var=ontap\_return

## get\_svms.yml (REST API)

---

- name: Get SVMs

collections:

- netapp.ontap

hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

tasks:

- name: Get details of configured SVMs

na\_ontap\_rest\_info:

use\_rest: always

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

gather\_subset:

- svm/svms

register: ontap\_return

- debug: var=ontap\_return

## create\_svm.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Onboard SVM

tasks:

- name: Create SVM

na\_ontap\_svm:

state: present

name: "{{ svmname }}"

use\_rest: always

services:

cifs:

allowed: false

fcp:

allowed: false

nfs:

allowed: true

enabled: true

aggr\_list: "{{ aggrlist }}"

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## set\_svm\_options.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Set SVM Options

tasks:

- name: Set SVM Options via CLI

na\_ontap\_command:

use\_rest: always

hostname: "{{ (inventory\_)hostname }}"

username: "{{ username }}"

password: "{{ password }}"

https: true

validate\_certs: false

command: ['set advanced -confirmations off; nfs modify -vserver "{{ svmname }}" -tcp-max-xfer-size 1048576; vol modify -vserver "{{ svmname }}" -volume "{{ datavolumename }}" -snapdir-access true; vol modify -vserver "{{ svmname }}" -volume "{{ datavolumename }}" -snapshot-policy none; vol modify -vserver "{{ svmname }}" -volume "{{ datavolumename }}" -atime-update false']

## create\_export\_policy.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Export Policy

tasks:

- name: Create Export Policy

na\_ontap\_export\_policy\_rule:

state: present

name: "{{ exportpolicyname }}"

vserver: "{{ svmname }}"

rule\_index: "{{ ruleindex }}"

client\_match: "{{ networkrange }}"

protocol: "{{ protocols }}"

hostname: "{{ (inventory\_)hostname }}"

ro\_rule : "{{ rorule }}"

rw\_rule: "{{ rwrule }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## create\_volume.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Onboard FlexVol

tasks:

- name: Create Volume

na\_ontap\_volume:

state: present

name: "{{ datavolumename }}"

aggregate\_name: "{{ dataaggrname }}"

use\_rest: always

size: "{{ datavolumesize }}"

size\_unit: "{{ sizeunit }}"

tiering\_policy: none

export\_policy: "{{ exportpolicyname }}"

percent\_snapshot\_space: 80

vserver: "{{ svmname }}"

junction\_path: '/{{ datavolumename }}'

wait\_for\_completion: True

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## create\_snapshot.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: SnapShot

tasks:

- name: Create SnapShot

na\_ontap\_snapshot:

state: present

snapshot: "{{ datavolumename }}{{ snapshotpostfix }}"

use\_rest: always

volume: "{{ datavolumename }}"

vserver: "{{ svmname }}"

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## restore\_snapshot.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Restore FlexVol

tasks:

- name: Restore Volume

na\_ontap\_volume:

state: present

name: "{{ datavolumename }}"

use\_rest: always

snapshot\_restore: "{{ datavolumename }}{{ snapshotpostfix }}"

vserver: "{{ svmname }}"

wait\_for\_completion: True

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## create\_clone.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Create FlexClone

tasks:

- name: Clone Volume

na\_ontap\_volume\_clone:

state: present

name: "{{ datavolumename }}{{ clonepostfix }}"

use\_rest: always

vserver: "{{ svmname }}"

junction\_path: '/{{ datavolumename }}{{ clonepostfix }}'

parent\_volume: "{{ datavolumename }}"

parent\_snapshot: "{{ datavolumename }}{{ snapshotpostfix }}"

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## delete\_clone.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Delete FlexClone

tasks:

- name: Delete Clone

na\_ontap\_volume:

state: absent

name: "{{ datavolumename }}{{ clonepostfix }}"

aggregate\_name: "{{ dataaggrname }}"

use\_rest: always

vserver: "{{ svmname }}"

wait\_for\_completion: True

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## delete\_snapshot.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: SnapShot

tasks:

- name: Delete SnapShot

na\_ontap\_snapshot:

state: absent

snapshot: "{{ datavolumename }}{{ snapshotpostfix }}"

use\_rest: always

volume: "{{ datavolumename }}"

vserver: "{{ svmname }}"

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## delete\_volume.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: Delete FlexVol

tasks:

- name: Delete Volume

na\_ontap\_volume:

state: absent

name: "{{ datavolumename }}"

aggregate\_name: "{{ dataaggrname }}"

use\_rest: always

vserver: "{{ svmname }}"

wait\_for\_completion: True

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

## delete\_svm.yml

---

- hosts: ontapservers|localhost - depending if inventory.yml will be used or variables

connection: local

collections:

- netapp.ontap

gather\_facts: false

name: SVM

tasks:

- name: Delete SVM

na\_ontap\_svm:

state: absent

name: "{{ svmname }}"

use\_rest: always

aggr\_list: "{{ aggrlist }}"

hostname: "{{ (inventory\_)hostname }}"

cert\_filepath: "{{ certfile }}"

key\_filepath: "{{ keyfile }}"

https: true

validate\_certs: false

# References

[https://netapp.io/2016/11/08/certificate-based-authentication-netapp-manageability-sdk-ontap/](https://netapp.io/2016/11/08/certificate-based-authentication-netapp-manageability-sdk-ontap/)

[https://docs.netapp.com/us-en/ontap/authentication/install-server-certificate-cluster-svm-ssl-server-task.html](https://docs.netapp.com/us-en/ontap/authentication/install-server-certificate-cluster-svm-ssl-server-task.html)

[https://docs.ansible.com/ansible/latest/collections/netapp/ontap/index.html](https://docs.ansible.com/ansible/latest/collections/netapp/ontap/index.html)

[https://netapp.io/2018/10/08/getting-started-with-netapp-and-ansible-install-ansible/](https://netapp.io/2018/10/08/getting-started-with-netapp-and-ansible-install-ansible/)

[https://docs.ansible.com/ansible/2.9/installation\_guide/intro\_installation.html](https://docs.ansible.com/ansible/2.9/installation_guide/intro_installation.html)

[https://galaxy.ansible.com/netapp/ontap](https://galaxy.ansible.com/netapp/ontap)

[https://github.com/ansible-collections/netapp.ontap](https://github.com/ansible-collections/netapp.ontap)
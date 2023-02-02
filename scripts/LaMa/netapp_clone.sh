#!/bin/bash

#Section - Variables
#########################################

VERSION="Version 0.9"

# Path for ansible play-books
ANSIBLE_PATH=/usr/sap/scripts/ansible

#Values for Ansible Inventory File
PRIMARY_CLUSTER=grenada
PRIMARY_SVM=svm-sap01
PRIMARY_KEYFILE=/usr/sap/scripts/ansible/certs/ontap.key
PRIMARY_CERTFILE=/usr/sap/scripts/ansible/certs/ontap.pem

#Default Variable if PARAM ClonePostFix / SnapPostFix is not maintained in LaMa
DefaultPostFix=_clone_1

#TMP Files - used during execution
YAML_TMP=/tmp/inventory_ansible_clone_tmp_$$.yml
TMPFILE=/tmp/tmpfile.$$

MY_NAME="`basename $0`"
BASE_SCRIPT_DIR="`dirname $0`"
# Sendig Script Version and run options to LaMa Log
echo "[DEBUG]: Running Script $MY_NAME $VERSION"
echo "[DEBUG]: $MY_NAME $@" 

#Command declared in the netapp_clone.conf Provider definition
#Command: /usr/sap/scripts/netapp_clone.sh --HookOperationName=$[HookOperationName] --SAPSYSTEMNAME=$[SAPSYSTEMNAME] --SAPSYSTEM=$[SAPSYSTEM] --MOUNT_XML_PATH=$[MOUNT_XML_PATH] --PARAM_ClonePostFix=$[PARAM-ClonePostFix] --PARAM_SnapPostFix=$[PARAM-SnapPostFix] --PROP_ClonePostFix=$[PROP-ClonePostFix] --PROP_SnapPostFix=$[PROP-SnapPostFix] --SAP_LVM_SRC_SID=$[SAP_LVM_SRC_SID] --SAP_LVM_TARGET_SID=$[SAP_LVM_TARGET_SID]   

#Reading Input Variables hand over by LaMa
for i in "$@"
do
case $i in
	--HookOperationName=*)
		HookOperationName="${i#*=}";shift;;
	--SAPSYSTEMNAME=*)
		SAPSYSTEMNAME="${i#*=}";shift;;
	--SAPSYSTEM=*)
		SAPSYSTEM="${i#*=}";shift;;
	--MOUNT_XML_PATH=*)
		MOUNT_XML_PATH="${i#*=}";shift;;
	--PARAM_ClonePostFix=*)
		PARAM_ClonePostFix="${i#*=}";shift;;
	--PARAM_SnapPostFix=*)
		PARAM_SnapPostFix="${i#*=}";shift;;
	--PROP_ClonePostFix=*)
		PROP_ClonePostFix="${i#*=}";shift;;
	--PROP_SnapPostFix=*)
		PROP_SnapPostFix="${i#*=}";shift;;
	--SAP_LVM_SRC_SID=*)
		SAP_LVM_SRC_SID="${i#*=}";shift;;
	--SAP_LVM_TARGET_SID=*)
		SAP_LVM_TARGET_SID="${i#*=}";shift;;
	*)
		# unknown option
	;;
esac
done

#If Parameters not provided by the User - defaulting to DefaultPostFix
if [ -z $PARAM_ClonePostFix ]; then PARAM_ClonePostFix=$DefaultPostFix;fi
if [ -z $PARAM_SnapPostFix ]; then PARAM_SnapPostFix=$DefaultPostFix;fi

# Debug
echo "HookOperationName: $HookOperationName">>/tmp/test.log
echo "SAPSYSTEMNAME: $SAPSYSTEMNAME">>/tmp/test.log
echo "SAPSYSTEM: $SAPSYSTEM">>/tmp/test.log
echo "SAP_LVM_SRC_SID: $SAP_LVM_SRC_SID">>/tmp/test.log
echo "SAP_LVM_TARGET_SID: $SAP_LVM_TARGET_SID">>/tmp/test.log


#Section - Functions
#########################################

#Function Create (Inventory) YML File
#########################################
create_yml_file()
{

echo "ontapservers:">$YAML_TMP
echo " hosts:">>$YAML_TMP
echo "  ${PRIMARY_CLUSTER}:">>$YAML_TMP
echo "   ansible_host: "'"'$PRIMARY_CLUSTER'"'>>$YAML_TMP
echo "   keyfile: "'"'$PRIMARY_KEYFILE'"'>>$YAML_TMP
echo "   certfile: "'"'$PRIMARY_CERTFILE'"'>>$YAML_TMP
echo "   svmname: "'"'$PRIMARY_SVM'"'>>$YAML_TMP
echo "   datavolumename: "'"'$datavolumename'"'>>$YAML_TMP
echo "   snapshotpostfix: "'"'$snapshotpostfix'"'>>$YAML_TMP
echo "   clonepostfix: "'"'$clonepostfix'"'>>$YAML_TMP
}
#Function run ansible-playbook
#########################################
run_ansible_playbook()
{
echo "[DEBUG]: Running ansible playbook netapp_lama_${HookOperationName}.yml on Volume $datavolumename"
ansible-playbook -i $YAML_TMP $ANSIBLE_PATH/netapp_lama_${HookOperationName}.yml 
}

#Section - Main
#########################################

#HookOperationName - CloneVolumes
#########################################

if [ $HookOperationName = CloneVolumes ] ;then
		
	#save mount xml for later usage - used in Section FinalizeCloneVolues to generate the mountpoints
	echo "[DEBUG]: saving mount config...."
	cp $MOUNT_XML_PATH /tmp/mount_config_${SAP_LVM_SRC_SID}_${SAPSYSTEM}.xml

	#Instance 00 + 01 share the same volumes - clone needs to be done once
	if [ $SAPSYSTEM != 01 ]; then

		#generating Volume List - assuming usage of qtrees - "IP-Adress:/VolumeName/qtree"
		xmlFile=/tmp/mount_config_${SAP_LVM_SRC_SID}_${SAPSYSTEM}.xml
		if [ -e $TMPFILE ];then rm $TMPFILE;fi
		numMounts=`xml_grep --count "/mountconfig/mount" $xmlFile | grep "total: " | awk '{ print $2 }'`
		i=1
	
		while [ $i -le $numMounts ]; do
     			xmllint --xpath "/mountconfig/mount[$i]/exportpath/text()" $xmlFile |awk -F"/" '{print $2}' >>$TMPFILE
			i=$((i + 1))
		done
		DATAVOLUMES=`cat  $TMPFILE |sort -u`

		#Create yml file and rund playbook for each volume
		for I in $DATAVOLUMES; do
			datavolumename="$I"
			snapshotpostfix="$PARAM_SnapPostFix"
			clonepostfix="$PARAM_ClonePostFix"
			create_yml_file
			
			run_ansible_playbook

		done
	else
		echo "[DEBUG]: Doing nothing .... Volume cloned in different Task"
	fi
fi

#HookOperationName - PostCloneVolumes
#########################################

if [ $HookOperationName = PostCloneVolumes ] ;then
	#Reporting Properties back to LaMa Config for Cloned System
	echo "[RESULT]:Property:ClonePostFix=$PARAM_ClonePostFix"
	echo "[RESULT]:Property:SnapPostFix=$PARAM_SnapPostFix"
	
	#Create MountPoint Config for Cloned Instances and report back to LaMa according to SAP Note: https://launchpad.support.sap.com/#/notes/1889590
	echo "MountDataBegin"
	echo '<?xml version="1.0" encoding="UTF-8"?>'
	echo "<mountconfig>"

	xmlFile=/tmp/mount_config_${SAP_LVM_SRC_SID}_${SAPSYSTEM}.xml
	numMounts=`xml_grep --count "/mountconfig/mount" $xmlFile | grep "total: " | awk '{ print $2 }'`
	i=1
	while [ $i -le $numMounts ]; do
		MOUNTPOINT=`xmllint --xpath "/mountconfig/mount[$i]/mountpoint/text()" $xmlFile`;
        	EXPORTPATH=`xmllint --xpath "/mountconfig/mount[$i]/exportpath/text()" $xmlFile`;
        	OPTIONS=`xmllint --xpath "/mountconfig/mount[$i]/options/text()" $xmlFile`;

		#Adopt Mountpoint towards Targed SID $SAPSYSTEMNAME
		# /home/hn2adm
		if [[ $MOUNTPOINT == *"home"* ]];then 
			SIDLOW=`echo $SAPSYSTEMNAME | tr [:upper:] [:lower:]`
	        	SIDADM=""$SIDLOW"adm"
			MOUNTPOINT="/home/$SIDADM"
		
		# /usr/sap/trans
		elif [[ $MOUNTPOINT == *"trans"* ]];then 
			# leave mountpoint as it is - MOUNTPOINT="/usr/sap/trans"
			MOUNTPOINT=$MOUNTPOINT
		
		# /sapmnt/HN2
		elif [[ $MOUNTPOINT == *"sapmnt"* ]];then 
			MOUNTPOINT="/sapmnt/$SAPSYSTEMNAME"
		# /usr/sap/HN2
		# /hana/data/H02
		# /hana/log/H02
		# /hana/shared/H02
		else		
			TMPFIELD1=`echo $MOUNTPOINT|awk -F"/" '{print $2}'`
			TMPFIELD2=`echo $MOUNTPOINT|awk -F"/" '{print $3}'`
			TMPFIELD3=`echo $MOUNTPOINT|awk -F"/" '{print $4}'`
			MOUNTPOINT="/"$TMPFIELD1"/"$TMPFIELD2"/"$SAPSYSTEMNAME
		fi
		#Adopt Exportpath and add Clonepostfix - assuming usage of qtrees - "IP-Adress:/VolumeName/qtree"
		TMPFIELD1=`echo $EXPORTPATH|awk -F":/" '{print $1}'`
		TMPFIELD2=`echo $EXPORTPATH|awk -F"/" '{print $2}'`
		TMPFIELD3=`echo $EXPORTPATH|awk -F"/" '{print $3}'`
		EXPORTPATH=$TMPFIELD1":/"${TMPFIELD2}$PARAM_ClonePostFix"/"$TMPFIELD3
		
		echo -e '\t<mount fstype="nfs" storagetype="NETFS">'
		echo -e "\t\t<mountpoint>${MOUNTPOINT}</mountpoint>"
		echo -e "\t\t<exportpath>${EXPORTPATH}</exportpath>"
		echo -e "\t\t<options>${OPTIONS}</options>"
		echo -e "\t</mount>"

		i=$((i + 1))
	done

	echo "</mountconfig>"
	echo "MountDataEnd"
	#Finished MountPoint Config

	#Cleanup Temporary Files
	rm $xmlFile
fi

#HookOperationName - ServiceConfigRemoval
#########################################

if [ $HookOperationName = ServiceConfigRemoval ] ;then
	#Assure that Properties ClonePostFix and SnapPostfix has been configured through the provisioning process 
	if [ -z $PROP_ClonePostFix ]; then echo "[ERROR]: Propertiy ClonePostFix is not handed over - please investigate";exit 5;fi
	if [ -z $PROP_SnapPostFix ]; then echo "[ERROR]: Propertiy SnapPostFix is not handed over - please investigate";exit 5;fi
	
	#Instance 00 + 01 share the same volumes - clone delete needs to be done once
	if [ $SAPSYSTEM != 01 ]; then
		#generating Volume List - assuming usage of qtrees - "IP-Adress:/VolumeName/qtree"
		xmlFile=$MOUNT_XML_PATH
		if [ -e $TMPFILE ];then rm $TMPFILE;fi
		numMounts=`xml_grep --count "/mountconfig/mount" $xmlFile | grep "total: " | awk '{ print $2 }'`
		i=1
		while [ $i -le $numMounts ]; do
     			xmllint --xpath "/mountconfig/mount[$i]/exportpath/text()" $xmlFile |awk -F"/" '{print $2}' >>$TMPFILE
			i=$((i + 1))
		done
		DATAVOLUMES=`cat  $TMPFILE |sort -u| awk -F $PROP_ClonePostFix '{ print $1 }'`

		#Create yml file and rund playbook for each volume
		for I in $DATAVOLUMES; do
			datavolumename="$I"
			snapshotpostfix="$PROP_SnapPostFix"
			clonepostfix="$PROP_ClonePostFix"
			create_yml_file

			run_ansible_playbook
		done
	else
		echo "[DEBUG]: Doing nothing .... Volume deleted in different Task"
	fi	
	
	#Cleanup Temporary Files
	rm $xmlFile
fi

#HookOperationName - ClearMountConfig
#########################################

if [ $HookOperationName = ClearMountConfig ] ;then
	#Assure that Properties ClonePostFix and SnapPostfix has been configured through the provisioning process 
	if [ -z $PROP_ClonePostFix ]; then echo "[ERROR]: Propertiy ClonePostFix is not handed over - please investigate";exit 5;fi
	if [ -z $PROP_SnapPostFix ]; then echo "[ERROR]: Propertiy SnapPostFix is not handed over - please investigate";exit 5;fi
	
	#Instance 00 + 01 share the same volumes - clone delete needs to be done once
	if [ $SAPSYSTEM != 01 ]; then
		#generating Volume List - assuming usage of qtrees - "IP-Adress:/VolumeName/qtree"
		xmlFile=$MOUNT_XML_PATH
		if [ -e $TMPFILE ];then rm $TMPFILE;fi
		numMounts=`xml_grep --count "/mountconfig/mount" $xmlFile | grep "total: " | awk '{ print $2 }'`
		i=1
		while [ $i -le $numMounts ]; do
     			xmllint --xpath "/mountconfig/mount[$i]/exportpath/text()" $xmlFile |awk -F"/" '{print $2}' >>$TMPFILE
			i=$((i + 1))
		done
		DATAVOLUMES=`cat  $TMPFILE |sort -u| awk -F $PROP_ClonePostFix '{ print $1 }'`

		#Create yml file and rund playbook for each volume
		for I in $DATAVOLUMES; do
			datavolumename="$I"
			snapshotpostfix="$PROP_SnapPostFix"
			clonepostfix="$PROP_ClonePostFix"
			create_yml_file

			run_ansible_playbook
		done
	else
		echo "[DEBUG]: Doing nothing .... Volume deleted in different Task"
	fi	
	
	#Cleanup Temporary Files
	rm $xmlFile
fi


#Cleanup
#########################################

#Cleanup Temporary Files
if [ -e $TMPFILE ];then rm $TMPFILE;fi
if [ -e $YAML_TMP ];then rm $YAML_TMP;fi

exit 0

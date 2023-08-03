#! /bin/bash
#########################################################################
# Version 1.1: 03/2022: Fixes in recovery logic with SID <> tenant name
# Version 2.0: 07/2023: - Same script can be used for SnapCenter and BlueXP backup recovery for HANA on ANF
#                       - Support of NFSv3, NFSv4.1 and SAN configured in SID specific cfg file     
#                       - List of tenants are read from HANA after system DB recovery
#                       - All tenants will then be recovered
#                       - Additional error handling at multiple places
#########################################################################

#########################################################################
# Required environment variables to be provided by caller
#########################################################################
# CLONED_VOLUMES_MOUNT_PATH: For NFS the script derives the IP address
# and the name of the cloned volume from the environment variable provided
# by SnapCenter and BlueXP backup and recovery 
# Example: CLONED_VOLUMES_MOUNT_PATH=192.168.175.117:/SS1_data_mnt00001_Clone_05112206115489411
#
# VOLUMES, jobId: For SAN the script gets the source volume name and the SnapCenter JobID
# from the environment provided by SnapCenter. The LUN path is then derived from
# the SnapCenter job log SC_LOG_PATH="/opt/NetApp/snapcenter/scc/logs"
#########################################################################

#########################################################################
# HANA system requirements
#########################################################################
# The data volume must be mounted at: MOUNT_POINT="/hana/data/$SID/mnt00001"
# (can be adapted in get_config_file function)
# HANA single host MDC systems with single or multiple tenants are supported
# HANA multiple host systems are not supported
#########################################################################


########################################################################
VERBOSE=NO
MY_NAME="`basename $0`"
BASE_SCRIPT_DIR="`dirname $0`"
VERSION="2.0"

#########################################################################
# Generic parameters
#########################################################################

# Timeout to start the database in 10sec intervals
# E.g. 3min = 180sec, TIME_OUT_STOP=18
TIME_OUT_START=60

# Timeout to stop the database in 10sec intervals
# E.g. 3min = 180sec, TIME_OUT_STOP=18
TIME_OUT_STOP=60

# log file writer
#################################
write2log()
{
   TEXT=$1
   echo -n `date +%Y%m%d%H%M%S` >> $LOGFILE
   echo -n "###" >> $LOGFILE
   echo -n `hostname` >> $LOGFILE
   echo "###$MY_NAME: $TEXT" >> $LOGFILE
   if [ "$VERBOSE" = "YES" ]
   then
      echo -n `date +%Y%m%d%H%M%S`
      echo -n "###"
      echo -n `hostname`
      echo "###$MY_NAME: $TEXT"
   fi
}

# Usage
#################################
usage()
{
   echo ""
   echo "Usage: $MY_NAME <operation> <SID> "
   echo "With operation = { mount | umount | recover | shutdown }"
   echo ""
}

# Get config file
#################################
get_config_file()
{
   RET=0
   CONFIG_FILE="$BASE_SCRIPT_DIR/sc-system-refresh-"$SID".cfg"
   if [ ! -e $CONFIG_FILE ]
   then
      echo "Config file $CONFIG_FILE does not exist."
      RET=1 
   else
      source $CONFIG_FILE
      MOUNT_POINT="/hana/data/$SID/mnt00001"
      INSTANCENO=`ls -al /hana/shared/$SID | grep HDB | awk -F B {'print $2'}`
      HDBNO="HDB$INSTANCENO"
      SIDLOW=`echo $SID | tr [:upper:] [:lower:]`
      SIDADM=""$SIDLOW"adm"
      LOGFILE="$BASE_SCRIPT_DIR/sc-system-refresh-"$SID".log"
      ENVFILE="$BASE_SCRIPT_DIR/env-from-sc-"$SID".txt"
      if [ ! -e $LOGFILE ]
      then
         touch $LOGFILE
         chmod 777 $LOGFILE
      fi
      case $PROTOCOL in
         "NFSv3")
            MOUNT_OPTIONS_NFS="rw,nfsvers=3,hard,timeo=600,rsize=1048576,wsize=262144,noatime,nolock 0 0";;
         "NFSv4.1")
            MOUNT_OPTIONS_NFS="rw,nfsvers=4.1,hard,timeo=600,rsize=1048576,wsize=262144,noatime,lock 0 0 ";;
         "SAN")
            MOUNT_OPTIONS_SAN="relatime,inode64";;
         *)
            echo "Error: Protocol not configured properly in $CONFIG_FILE"
            write2log "Error: Protocol not configured properly in $CONFIG_FILE"
	    RET=1;;
      esac

      # Save env for debugging 
      /usr/bin/env > $ENVFILE 
   fi
}

# Umount operation
#################################
umount_data_volume()
{
   write2log "Unmounting data volume."
   if [ $PROTOCOL = "SAN" ]
   then
      UUID=`cat /etc/fstab | grep \/hana\/data | awk -F \/ {'print $4'}`
   fi

   UMOUNT_CMD="umount $MOUNT_POINT"
   write2log "$UMOUNT_CMD" 
   $UMOUNT_CMD
   RET=$?
   if [ $RET -gt 0 ]
   then
      write2log "Unmount operation failed."
   else
      write2log "Deleting /etc/fstab entry."
      sed -i "/\/hana\/data/d" /etc/fstab
      write2log "Data volume unmounted successfully."
   fi

   if [ $PROTOCOL = "SAN" ]
   then
      write2log "Removing multipath map and device files."
      LUN_PATH=`cat $BASE_SCRIPT_DIR/LUN_PATH.txt`
      rm $BASE_SCRIPT_DIR/DEVICE_NO.txt
      /usr/sbin/sanlun lun show | grep $LUN_PATH | awk {'print $3'} | awk -F \/ {'print $3'} | while read DEVICE;
      do
         write2log "$DEVICE"
         DEVICE_NO=`multipath -ll | grep $DEVICE | awk {'print $2'}`
         echo $DEVICE_NO >> $BASE_SCRIPT_DIR/DEVICE_NO.txt
      done
      /sbin/multipath -f $UUID
      cat $BASE_SCRIPT_DIR/DEVICE_NO.txt | while read DEVICE_NO;
      do
         write2log "echo 1 > /sys/bus/scsi/devices/$DEVICE_NO/delete"
         echo 1 > /sys/bus/scsi/devices/$DEVICE_NO/delete
      done
   fi
}

# Get status of HANA database 
#################################
wait_for_status()
{
   CMD="sapcontrol -nr $INSTANCENO -function GetSystemInstanceList | grep HDB | awk -F , {'print \$7'}"
   STATUS=`su - $SIDADM -c "$CMD"`
   STATUS=`echo $STATUS | sed 's/ *$//g'`
   if [ "$STATUS" != "GRAY" -a "$STATUS" != "YELLOW" -a "$STATUS" != "GREEN" ]
   then
      write2log "Error: Unexpected status from sapcontrol -nr $INSTANCENO -function GetSystemInstanceList."	   
      write2log "Status: $STATUS"
      RET=2
      return
   fi

   EXPECTED_STATUS=$1
   TIME_OUT=$2
   CHECK=1
   COUNT=0
   while [ $CHECK = 1 ]; do
      CMD="sapcontrol -nr $INSTANCENO -function GetSystemInstanceList | grep HDB | awk -F , {'print \$7'}"
      STATUS=`su - $SIDADM -c "$CMD"`
      write2log "Status: $STATUS"
      if [ $STATUS = $EXPECTED_STATUS ]
      then
         CHECK=0
         RET=0
      else
         sleep 10 
         COUNT=`expr $COUNT + 1`
         if [ $COUNT -gt $TIME_OUT ]
         then
            RET=1
            CHECK=0 
         fi
      fi
   done
}

# Stop HANA database
#################################
stop_hana_db()
{
   write2log "Stopping HANA database."
   CMD="sapcontrol -nr $INSTANCENO -function StopSystem HDB"
   write2log "$CMD"
   su - $SIDADM -c "$CMD >> $LOGFILE 2>&1"

   write2log "Wait until SAP HANA database is stopped ...." 
   wait_for_status GRAY $TIME_OUT_STOP 
   if [ $RET -gt 0 ]
   then
      if [ $RET = 1 ]
      then
         write2log "Timeout error: SAP HANA database not stopped configured timeout."
         echo "Timeout error: SAP HANA database not stopped within configured timeout."
         RET=1
      elif [ $RET = 2 ]
      then
         write2log "Error in sapcontrol execution."
         echo "Error in sapcontrol execution."
         RET=2
      fi
   else
      write2log "SAP HANA database is stopped."
      RET=0
   fi
}

# Discover LUN 
#################################
discover_lun()
{
   write2log "Discover LUN and get UUID."
   SC_LOG_PATH="/opt/NetApp/snapcenter/scc/logs"

   write2log "Get source volume name and SnapCenter job ID from environment."
   SOURCE_VOLUME=`/usr/bin/env | grep "VOLUMES=" | awk -F = {'print $2'} | awk -F : {'print $2'}`
   JOB_ID=`/usr/bin/env | grep "jobId=" | awk -F = {'print $2'}`
   write2log "Source volume: $SOURCE_VOLUME"
   write2log "SnapCenter job ID: $JOB_ID"

   write2log "Get volume and LUN name from SnapCenter log file."
   LUN_PATH=`grep \<LunPath\> $SC_LOG_PATH/hana_$JOB_ID.log | grep $SOURCE_VOLUME | grep -v \/$SOURCE_VOLUME\/ | tr -d " " | uniq | awk -F \> {'print $2'} | awk -F \< {'print $1'}`
   write2log "$LUN_PATH"
   echo $LUN_PATH > $BASE_SCRIPT_DIR/LUN_PATH.txt

   write2log "Rescan SCSI bus."
   /usr/bin/rescan-scsi-bus.sh -a

   write2log "Get device name."
   /usr/sbin/sanlun lun show | grep $LUN_PATH >> /root/env_$JOB_ID.data
   DEVICE=`/usr/sbin/sanlun lun show | grep $LUN_PATH | head -n1 | awk {'print $3'}`

   write2log "Get UUID of LUN."
   UUID=`/lib/udev/scsi_id -g -u -d $DEVICE`

   write2log "Device: $DEVICE"
   write2log "LUN UUID: $UUID"
}

# Mount operation
#################################
mount_data_volume()
{
   write2log "Adding entry in /etc/fstab."
   if [ $PROTOCOL = "NFSv3" -o "NFSv4.1" ]
   then
      # Get SVM IP and junction path from environment provided by SC
      STORAGE=`echo $CLONED_VOLUMES_MOUNT_PATH | awk -F : {'print $1'}`
      JUNCTION_PATH=`echo $CLONED_VOLUMES_MOUNT_PATH |  awk -F : {'print $2'}`
      LINE="$STORAGE":"$JUNCTION_PATH $MOUNT_POINT nfs $MOUNT_OPTIONS_NFS"
      write2log "$LINE"
      echo $LINE >> /etc/fstab
   fi
   if [ $PROTOCOL = "SAN" ]
   then
      LINE="/dev/mapper/$UUID $MOUNT_POINT xfs $MOUNT_OPTIONS_SAN 0 0"
      write2log "$LINE"
      echo $LINE >> /etc/fstab
   fi

   MOUNT_CMD="mount $MOUNT_POINT"
   write2log "Mounting data volume: $MOUNT_CMD."
   $MOUNT_CMD
   RET=$?
   if [ $RET -gt 0 ]
   then
      write2log "Mount operation failed."
      return $RET
   else
      write2log "Data volume mounted successfully."
      write2log "Change ownership to $SIDADM."
      chown -R $SIDADM:sapsys $MOUNT_POINT 
   fi
}

# Recovery operation
#################################
recover_database()
{
   write2log "Recover system database."

   SQL="RECOVER DATA USING SNAPSHOT CLEAR LOG"
   RECOVER_CMD="/usr/sap/$SID/$HDBNO/exe/Python/bin/python /usr/sap/$SID/$HDBNO/exe/python_support/recoverSys.py --command \"$SQL\""
   write2log "$RECOVER_CMD" 
   su - $SIDADM -c "$RECOVER_CMD"

   write2log "Wait until SAP HANA database is started ...." 
   wait_for_status GREEN $TIME_OUT_START 
   if [ $RET -gt 0 ]
   then
      write2log "Timeout error: SAP HANA database not started within configured timeout."
      echo "Timeout error: SAP HANA database not started within configured timeout."
      RET=1
   else
      write2log "HANA system database started."
      RET=0
   fi

   if [ $RET -eq 0 ]
   then
      write2log "Checking connection to system database."
      HDB_SQL_CMD="/usr/sap/$SID/SYS/exe/hdb/hdbsql"
      SQL="select * from sys.m_databases;"
      TEST_CMD="$HDB_SQL_CMD -U $KEY '$SQL'"
      write2log "$TEST_CMD"
      su - $SIDADM -c "$TEST_CMD >> $LOGFILE 2>&1"
      RET=$?
      if [ $RET -gt 0 ]
      then
         write2log "Error: Cannot connect to system databse using $KEY"
      else
         write2log "Succesfully connected to system database."
      fi
      if [ $RET -eq 0 ]
      then
         HDB_SQL_CMD="/usr/sap/$SID/SYS/exe/hdb/hdbsql"
         TENANT_LIST=$(su - $SIDADM -c "$HDB_SQL_CMD -U $KEY SELECT DATABASE_NAME from M_DATABASES WHERE ACTIVE_STATUS=\'NO\'"| grep -oe '"\w*"'|sed -e 's/"//g')
         write2log "Tenant databases to recover: $TENANT_LIST"
         if [ -z "$TENANT_LIST" ]
         then
	   write2log "There are no inactive tenants to recover"
         else 
	    write2log "Found inactive tenants($TENANT_LIST) and starting recovery"
            for TENANT in $TENANT_LIST
            do
               write2log "Recover tenant database "$TENANT"." 
               SQL="RECOVER DATA FOR $TENANT USING SNAPSHOT CLEAR LOG"
               RECOVER_CMD="$HDB_SQL_CMD -U $KEY $SQL"
               write2log "$RECOVER_CMD"
               su - $SIDADM -c "$RECOVER_CMD >> $LOGFILE 2>&1"
               write2log "Checking availability of Indexserver for tenant "$TENANT"."
               CMD="sapcontrol -nr $INSTANCENO -function GetProcessList | grep Indexserver-$TENANT | awk -F , '{print \$3}'"
               RETSTR=`su - $SIDADM -c "$CMD"`
               RETSTR=`echo $RETSTR | sed 's/^ *//g'`
               if [ "$RETSTR" != "GREEN" ]
               then
                  write2log "Recovery of tenant database $TENANT failed."
                  echo "Recovery of tenant database $TENANT failed."
                  write2log "Status: $RETSTR"
                  RET=1
               else
                  write2log "Recovery of tenant database $TENANT succesfully finished."
                  write2log "Status: $RETSTR"
                  RET=0
               fi
            done
         fi
      fi
   fi
}

# Main 
#################################
if [ "$1" ]
then TASK=$1
   if [ $TASK != "mount" -a $TASK != "umount" -a $TASK != "recover" -a $TASK != "shutdown" ]
   then
      echo "Wrong operation parameter. Must be mount, umount, recover or shutdown."
      usage 
      exit 1
   fi
else 
   echo "Wrong operation parameter."
   usage
   exit 1
fi

if [ "$2" ]
then
   SID=$2
   get_config_file
   if [ $RET -gt 0 ]
   then
      exit 1
   fi
else
   echo "Wrong Parameter: SID must be provided."
   usage
   exit 1
fi


write2log "***************************************************************************************"
write2log "Script version: $VERSION"

case $TASK in

   "shutdown")
   write2log "********************** Starting script: shutdown operation **************************"
   stop_hana_db
   write2log "********************** Finished script: shutdown operation **************************"
   exit $RET
   ;;

   "umount")
   write2log "********************** Starting script: umount operation **************************"
   umount_data_volume
   write2log "********************** Finished script: umount operation **************************"
   exit $RET
   ;;

   "recover")
   write2log "********************** Starting script: recovery operation **************************"
   recover_database
   write2log "********************** Finished script: recovery operation **************************"

   # For debugging of recovery issues, set exit code to 0
   # This avoids cleanup process of SnapCenter
   # exit 0 
   exit $RET
   ;;

   "mount") 
   if [ $PROTOCOL = "NFSv3" -o "NFSv4,1" ]
   then
      write2log "********************** Starting script: mount operation **************************"
      mount_data_volume
      write2log "********************** Finished script: mount operation **************************"
      # For debugging, set exit code to 0
      # This avoids cleanup process of SnapCenter
      # exit 0 
      exit $RET
   fi 
   if [ $PROTOCOL = "SAN" ]
   then
      write2log "********************** Starting script: mount operation **************************"
      discover_lun
      mount_data_volume
      write2log "********************** Finished script: mount operation **************************"
      # For debugging, set exit code to 0
      # This avoids cleanup process of SnapCenter
      # exit 0 
      exit $RET
   fi
   ;;
esac


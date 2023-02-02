#! /bin/bash
#########################################################################
# Version 1.1: 03/2022: Fixes in recovery logic with SID <> tenant name
#########################################################################

VERBOSE=NO
MY_NAME="`basename $0`"
BASE_SCRIPT_DIR="`dirname $0`"
VERSION="1.1"

#########################################################################
# Generic parameters
#########################################################################

MOUNT_OPTIONS_NFS="rw,vers=3,hard,timeo=600,rsize=1048576,wsize=1048576,intr,noatime,nolock"
MOUNT_OPTIONS_SAN="relatime,inode64"

# Timeout to start the database in 10sec intervals
# E.g. 3min = 180sec, TIME_OUT_STOP=18
TIME_OUT_START=18

# Timeout to stop the database in 10sec intervals
# E.g. 3min = 180sec, TIME_OUT_STOP=18
TIME_OUT_STOP=18

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
      HANA_ARCHITECTURE=`/usr/bin/env | grep HANA_DATABASE_TYPE | awk -F = {'print $2'}`
      # Save env for debugging 
      /usr/bin/env > $ENVFILE 
      RET=0
   fi
}

# Umount operation
#################################
umount_data_volume()
{
   write2log "Unmounting data volume."
   if [ $PROTOCOL = "SAN" ]
   then
      UUID=`cat /etc/fstab | grep \/hana\/data\/$SID | awk -F \/ {'print $4'}`
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
      sed -i "/\/hana\/data\/$SID/d" /etc/fstab
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
            break
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
      write2log "Timeout error: SAP HANA database not stopped configured timeout."
      echo "Timeout error: SAP HANA database not stopped within configured timeout."
      RET=1
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
   if [ $PROTOCOL = "NFS" ]
   then
      # Get SVM IP and junction path from environment provided by SC
      STORAGE=`/usr/bin/env | grep CLONED_VOLUMES_MOUNT_PATH | awk -F = {'print $2'} | awk -F : {'print $1'}`
      JUNCTION_PATH=`/usr/bin/env | grep CLONED_VOLUMES_MOUNT_PATH | awk -F = {'print $2'} | awk -F : {'print $2'}`
      LINE="$STORAGE":"$JUNCTION_PATH $MOUNT_POINT nfs $MOUNT_OPTIONS_NFS 0 0"
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
   if [ $HANA_ARCHITECTURE="MULTIPLE_CONTAINERS" ]
   then
      write2log "Recover system database."
   else
      write2log "Recover single container database."
   fi

   SQL="RECOVER DATA USING SNAPSHOT CLEAR LOG"
   RECOVER_CMD="/usr/sap/$SID/$HDBNO/exe/Python/bin/python /usr/sap/$SID/$HDBNO/exe/python_support/recoverSys.py --command \"$SQL\""
   write2log "$RECOVER_CMD" 
#   su - $SIDADM -c "$RECOVER_CMD >> $LOGFILE 2>&1"
   su - $SIDADM -c "$RECOVER_CMD"

   write2log "Wait until SAP HANA database is started ...." 
   wait_for_status GREEN $TIME_OUT_START 
   if [ $RET -gt 0 ]
   then
      write2log "Timeout error: SAP HANA database not started within configured timeout."
      echo "Timeout error: SAP HANA database not started within configured timeout."
      RET=1
   else
      write2log "SAP HANA database is started."
      RET=0
   fi

   if [ $HANA_ARCHITECTURE="MULTIPLE_CONTAINERS" -a $RET -eq 0 ]
   then
      SECOND_TENANT_IN_LIST=`/usr/bin/env | grep TENANT_DATABASE_NAMES | awk -F = '{print $2}' | awk -F , '{print $2}'`
      if [ $SECOND_TENANT_IN_LIST ]
      then 
         write2log "Source system contains more than one tenant, recovery will only be executed for the first tenant."
         TENANT_LIST=`/usr/bin/env | grep TENANT_DATABASE_NAMES | awk -F = '{print $2}'`
	 write2log "List of tenants: $TENANT_LIST" 
         TENANT=`/usr/bin/env | grep TENANT_DATABASE_NAMES | awk -F = '{print $2}' | awk -F , '{print $1}'`
      else
         SOURCE_TENANT=`/usr/bin/env | grep TENANT_DATABASE_NAMES | awk -F = '{print $2}'`
         SOURCE_SID=`/usr/bin/env | grep TENANT_DATABASE_NAMES | sed -e "s;^MDC.;;g" | awk -F _ '{print $1}'` 
         write2log "Source Tenant: $SOURCE_TENANT"
         write2log "Source SID: $SOURCE_SID"
	 if [ "$SOURCE_TENANT" != "$SOURCE_SID" ]
	 then
            TENANT=$SOURCE_TENANT
	    write2log "Source system has a single tenant: $TENANT"
	    write2log "Target tenant will have the same name. Tenant rename can be excuted after recovery, if required."
	 else
            TENANT=$SID
	    write2log "Source system has a single tenant and tenant name is identical to source SID: $SOURCE_TENANT"
	    write2log "Target tenant will have the same name as target SID: $SID."
         fi
      fi
      write2log "Recover tenant database "$TENANT"." 
      SQL="RECOVER DATA FOR $TENANT USING SNAPSHOT CLEAR LOG"
      RECOVER_CMD="/usr/sap/$SID/SYS/exe/hdb/hdbsql -U $KEY $SQL"
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

write2log "Version: $VERSION"

case $TASK in

   "shutdown")
   stop_hana_db
   exit $RET
   ;;

   "umount")
   umount_data_volume
   exit $RET
   ;;

   "recover")
   recover_database
   # For debugging of recovery issues, set exit code to 0
   # This avoids cleanup process of SnapCenter
   exit 0 
   #exit $RET
   ;;

   "mount") 
   if [ $PROTOCOL = "NFS" ]
   then
      mount_data_volume
      # For debugging, set exit code to 0
      # This avoids cleanup process of SnapCenter
      exit 0 
      #exit $RET
   fi 
   if [ $PROTOCOL = "SAN" ]
   then
      discover_lun
      mount_data_volume
      # For debugging, set exit code to 0
      # This avoids cleanup process of SnapCenter
      # exit 0 
      exit $RET
   fi
   ;;
esac


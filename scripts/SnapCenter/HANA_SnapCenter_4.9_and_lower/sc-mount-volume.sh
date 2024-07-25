#! /bin/bash
VERBOSE=NO
MY_NAME="`basename $0`"
BASE_SCRIPT_DIR="`dirname $0`"

#########################################################################
# Generic parameters
#########################################################################

MOUNT_OPTIONS_NFS="rw,vers=3,hard,timeo=600,rsize=1048576,wsize=1048576,intr,noatime,nolock"

# log file writer
#################################
write2log()
{
   TEXT=$1
   echo -n `date +%Y%m%d%H%M%S` >> $LOGFILE
   echo -n "###" >> $LOGFILE
   echo -n `hostname` >> $LOGFILE
   echo "###$MY_NAME: $TEXT" >> $LOGFILE
   if [ $VERBOSE = YES ]
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
   echo "Usage: $MY_NAME <mount | umount> <mount point> <SID>"
   echo ""
}

# Mount operation
#################################
mount_volume()
{
   write2log "Adding entry in /etc/fstab."
   # Get SVM IP and junction path from environment provided by SC
   STORAGE=`/usr/bin/env | grep CLONED_VOLUMES_MOUNT_PATH | awk -F = {'print $2'} | awk -F : {'print $1'}`
   JUNCTION_PATH=`/usr/bin/env | grep CLONED_VOLUMES_MOUNT_PATH | awk -F = {'print $2'} | awk -F : {'print $2'}`
   # Covering NetApp best practices to put /usr/sap and /hana/shared in the same volume
   if [ $MOUNT_POINT = "usr-sap-and-shared" ]
   then
      LINE="$STORAGE":"$JUNCTION_PATH/usr-sap /usr/sap/$SID nfs $MOUNT_OPTIONS_NFS 0 0"
      write2log "$LINE"
      echo $LINE >> /etc/fstab
      MOUNT_CMD="mount /usr/sap/$SID"
      write2log "Mounting volume: $MOUNT_CMD."
      $MOUNT_CMD
      RET=$?
      if [ $RET -eq 0 ]
      then
         LINE="$STORAGE":"$JUNCTION_PATH/shared /hana/shared nfs $MOUNT_OPTIONS_NFS 0 0"
         write2log "$LINE"
         echo $LINE >> /etc/fstab
         MOUNT_CMD="mount /hana/shared"
         write2log "Mounting volume: $MOUNT_CMD."
         $MOUNT_CMD
         RET=$?
      fi
   else
      LINE="$STORAGE":"$JUNCTION_PATH $MOUNT_POINT nfs $MOUNT_OPTIONS_NFS 0 0"
      write2log "$LINE"
      echo $LINE >> /etc/fstab
      MOUNT_CMD="mount $MOUNT_POINT"
      write2log "Mounting volume: $MOUNT_CMD."
      $MOUNT_CMD
      RET=$?
   fi 

   if [ $RET -gt 0 ]
   then
      write2log "Mount operation failed."
      return $RET
   else
      write2log "$MOUNT_POINT mounted successfully."
      write2log "Change ownership to $SIDADM."
      chown -R $SIDADM:sapsys $MOUNT_POINT 
   fi
}

# Umount operation
#################################
umount_volume()
{
   # Covering NetApp best practices to put /usr/sap and /hana/shared in the same volume
   if [ $MOUNT_POINT = "usr-sap-and-shared" ]
   then
      write2log "Unmounting /usr/sap/$SID."
      UMOUNT_CMD="umount /usr/sap/$SID"
      $UMOUNT_CMD
      RET=$?
      if [ $RET -eq 0 ]
      then
         write2log "Unmounting /hana/shared."
         UMOUNT_CMD="umount /hana/shared"
         $UMOUNT_CMD
         RET=$?
      fi
      if [ $RET -eq 0 ]
      then
         JUNCTION_PATH=`grep /hana/shared /etc/fstab | awk -F " " '{print $1}' | awk -F / '{print $2}'`
         write2log "Junction path: $JUNCTION_PATH"
         write2log "Deleting /etc/fstab entry."
         sed -i "/$JUNCTION_PATH/d" /etc/fstab
         write2log "/usr/sap/$SID and /hana/shared unmounted successfully."
      fi
      if [ $RET -gt 0 ]
      then
         write2log "Unmount operation failed."
      fi
   else
      write2log "Unmounting $MOUNT_POINT."
      JUNCTION_PATH=`grep $MOUNT_POINT /etc/fstab | awk -F " " '{print $1}' | awk -F / '{print $2}'`
      write2log "Junction path: $JUNCTION_PATH"

      UMOUNT_CMD="umount $MOUNT_POINT"
      $UMOUNT_CMD
      RET=$?
      if [ $RET -gt 0 ]
      then
         write2log "Unmount operation failed."
      else
         write2log "Deleting /etc/fstab entry."
         sed -i "/$JUNCTION_PATH/d" /etc/fstab
         write2log "$MOUNT_POINT unmounted successfully."
      fi
   fi
}


# Main 
#################################
if [ "$1" ]
then TASK=$1
   if [ $TASK != "mount" -a $TASK != "umount" ]
   then
      echo "Wrong operation parameter. Must be mount or umount."
      usage
      exit 1
   fi
else
   echo "Missing parameter."
   usage
   exit 1
fi


if [ "$2" ]
then 
   MOUNT_POINT=$2
else 
   echo "Missing parameter."
   usage
   exit 1
fi

if [ "$3" ]
then
   SID=$3
else 
   echo "Missing parameter."
   usage
   exit 1
fi

LOGFILE="$BASE_SCRIPT_DIR/sc-mount-volume.log"
if [ ! -e $LOGFILE ]
then
   touch $LOGFILE
   chmod 777 $LOGFILE
fi

SIDLOW=`echo $SID | tr [:upper:] [:lower:]`
SIDADM=""$SIDLOW"adm"

case $TASK in

   "mount")
   mount_volume 
   # For debugging, set exit code to 0
   # This avoids cleanup process of SnapCenter
   exit 0
   # exit $RET
   ;;

   "umount")
   umount_volume
   exit $RET
   ;;

esac


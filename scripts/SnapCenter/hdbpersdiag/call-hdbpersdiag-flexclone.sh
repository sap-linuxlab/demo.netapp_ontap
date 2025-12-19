#! /bin/bash

# hdbpersdiag parameter "-e" is used for encrypted data volume
# Need to be adapted if volume is not encrypted
#
# SID of the cloned source system is provided by SnapCenter in env variable MDCSS2_HANA_DATABASE_SID
# e.g. MDCSS2_HANA_DATABASE_SID=SS2
#

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
####################################################################
# Main
####################################################################

MY_NAME="`basename $0`"
BASE_SCRIPT_DIR="`dirname $0`"
SID=`ps -ef | grep sap | grep sapstartsrv | grep HDB | awk -F sap '{print $2}' | awk -F "/" '{print $2}'`
SIDLOW=`echo $SID | tr [:upper:] [:lower:]`
SIDADM="$SIDLOW"adm

MY_NAME_SHORT=`echo $MY_NAME | awk -F . '{print $1}'`
LOGFILE="$BASE_SCRIPT_DIR/$MY_NAME_SHORT"-$SID".log"
if [ ! -e $LOGFILE ]
 then
    touch $LOGFILE
    chmod 777 $LOGFILE
 fi

write2log "Executing hdbpersdiag for source system $MDCSS2_HANA_DATABASE_SID."
write2log "Clone mounted at /hana/data/$SID/mnt00001."  

# Get all hdbxxxxx.xxxxx directories in Snapshot backup
directories=($(ls -d /hana/data/$SID/mnt00001/hdb*))

# Loop through each directory 
for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        write2log "Executing hdbpersdiag in: $dir"
	CMD="hdbpersdiag -e -c \"check all\" $dir"
	RETSTRING=$(su - $SIDADM -c "$CMD 2>&1")
	write2log "$RETSTRING"
	# any error messages?
	echo $RETSTRING | grep ERROR
	if [ $? -eq 0 ]
	then
	   write2log "Error in hdbpersdiag operation for volume $dir."
           exit 1
	else
	   write2log "Consistency check operation successful for volume $dir."
	fi	   
    fi
done
exit 0

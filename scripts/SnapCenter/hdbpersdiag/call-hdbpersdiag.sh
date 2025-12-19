#! /bin/bash

# hdbpersdiag parameter "-e" is used for encrypted data volume
# Need to be adapted if volume is not encrypted
# Snapshot name is provided by SnapCenter in env variable SNAME
# Policy name is provided by SnapCenter in env variable POLICY
#
#############################
# Parameter
# ###########################
# hdbpersdaig will only be executed on this day
RUN_DAYOFWEEK="Sunday"
# hdbpersdaig will only be executed when called with this SnapCenter policy
RUN_POLICY="SnapAndCallHdbpersdiag"

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

if [ "$POLICY" != "$RUN_POLICY" ] 
then 
   write2log "Script was called with policy $POLICY, consistency check is only done when called with policy $RUN_POLICY"
   exit;
else
   write2log "Script was called with policy $POLICY"
   day=$(date +"%A")
   if [ "$day" != "$RUN_DAYOFWEEK" ]
   then
      write2log "Current day is $day, consistency check is only executed once per week on $RUN_DAYOFWEEK"
      exit
   fi
fi


# Get all hdbxxxxx.xxxxx directories in Snapshot backup
directories=($(ls -d /hana/data/$SID/mnt00001/.snapshot/$SNAME/hdb*)) 

# Loop through each directory 
for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        write2log "Executing hdbpersdiag in: $dir"
	CMD="hdbpersdiag  --force -e -c \"check all\" $dir"
	RETSTRING=$(su - $SIDADM -c "$CMD 2>&1")
	write2log "$RETSTRING"
	# any error messages?
	echo $RETSTRING | grep ERROR
	if [ $? -eq 0 ]
	then
	   write2log "Error in hdbpersdiag operation for volume $dir."
           exit 1
	else
	   write2log "Consistency check operation successeful for volume $dir."
	fi	   
    fi
done
exit 0

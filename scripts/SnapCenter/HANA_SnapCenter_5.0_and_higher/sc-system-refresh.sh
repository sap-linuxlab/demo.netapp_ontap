#! /bin/bash
#########################################################################
# Version 1.1: 03/2022: Fixes in recovery logic with SID <> tenant name
# Version 2.0: 07/2027: - Same script can be used for SnapCenter and BlueXP backup recovery for HANA on ANF
#                       - Support of NFSv3, NFSv4.1 and SAN configured in SID specific cfg file     
#                       - List of tenants are read from HANA after system DB recovery
#                       - All tenants will then be recovered
#                       - Additional error handling at multiple places
# Version 2.1: 08/2023: - Validation and fixes for SAN support
#                       - Minor general fixes
# Version 3.0: 04/2024: - New version for SC5.0 where mount/unmount is not required
#                       - Removed mount/unmount operations
#                       - No configuration file required anymore
#########################################################################

#########################################################################
# <sid>adm user must be configured with Bourne shell, c-shell is not supported
#
# Supported HANA system configurations:
# - single host MDC systems with single or multiple tenants
# - HSR primary host can be used as a source system (target can be HSR-enabled or not)
# 
# Unsupported HANA system configurations:
# - HANA multiple host systems
#########################################################################

#########################################################################
# Validated OS and SnapCenter releases
#########################################################################
# The script has been validated with
# - SnapCenter 5.0N: SLES 15 SP3
# Other SLES releases will most probably work as well, but requires testing.
# 
# RHEL has not been validated. 
#########################################################################


########################################################################
VERBOSE=YES
MY_NAME="`basename $0`"
BASE_SCRIPT_DIR="`dirname $0`"
VERSION="3.0"

#########################################################################
# Generic parameters
#########################################################################

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
   echo "Usage: $MY_NAME <operation> "
   echo "With operation = { recover | shutdown }"
   echo ""
}

# Get config file
#################################
set_config()
{
   RET=0
   SID=`ps -ef | grep sap | grep sapstartsrv | grep HDB | awk -F sap '{print $2}' | awk -F "/" '{print $2}'`
   INSTANCENO=`ls -al /hana/shared/$SID | grep HDB | awk -F B {'print $2'}`
   HDBNO="HDB$INSTANCENO"
   SIDLOW=`echo $SID | tr [:upper:] [:lower:]`
   SIDADM=""$SIDLOW"adm"
   MY_NAME_SHORT=`echo $MY_NAME | awk -F . '{print $1}'`
   LOGFILE="$BASE_SCRIPT_DIR/$MY_NAME_SHORT"-$SID".log"
   if [ ! -e $LOGFILE ]
   then
      touch $LOGFILE
      chmod 777 $LOGFILE
   fi
   CMD="hdbuserstore list | grep $SID"KEY""
   RETSTR=`su - $SIDADM -c "$CMD"`
   if [ -z "$RETSTR" ]
   then
      echo"Userstore key $SID"KEY" not found, please configure key as user $SIDADM"
      write2log"Userstore key $SID"KEY" not found, please configure key as user $SIDADM"
      RET=1
   else
      KEY=$SID"KEY"
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

   write2log "Wait until SYSTEM database is stopped ...." 
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
   if [ $TASK != "recover" -a $TASK != "shutdown" ]
   then
      echo "Wrong operation parameter. Must be recover or shutdown."
      usage 
      exit 1
   fi
else 
   echo "Wrong operation parameter."
   usage
   exit 1
fi

set_config
if [ $RET -eq 1 ]
then
   exit 1
fi

write2log "**********************************************************************************"
write2log "Script version: $VERSION"

case $TASK in

   "shutdown")
   write2log "******************* Starting script: shutdown operation **************************"
   stop_hana_db
   write2log "******************* Finished script: shutdown operation **************************"
   exit $RET
   ;;

   "recover")
   write2log "******************* Starting script: recovery operation **************************"
   recover_database
   write2log "******************* Finished script: recovery operation **************************"

   # For debugging of recovery issues, set exit code to 0
   # This avoids cleanup process of SnapCenter
   #exit 0 
   exit $RET
   ;;
esac


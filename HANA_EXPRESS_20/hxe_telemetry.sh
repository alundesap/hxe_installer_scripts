#!/bin/bash
############################################################################################
# Print usage
############################################################################################
usage() {
cat <<-EOF


NAME
   $base_name

SYNOPSIS
   $base_name [options]

DESCRIPTION
   The $base_name utility enables and disables telemetry, changes the telemetry server url and reports on the status of telemetry on a database. 
   Enabling and disabling telemetry and changing the server url will take effect after the next scheduled transmission time.
   
   This utility must be run by a user that is able to execute hdbsql commands and has hdbsql in the path. 

OPTIONS
  Generic Program Information
      -h, --help
             Print a usage message briefly summarizing these command-line options, then exit.  

  Connection Information  
      -u, --user
             Database technical user name. The user must have permission to alter the global.ini file and to read from system tables.
             The default value is "system".
   
      -p, --password
             Database technical user password. If the password is not entered on the command line, the user will be prompted to enter the password.
             There is no default value.
   
      -i, --instance 
             The instance number of the HANA database server. 
             The default value is "90".
 
      -d, --database
             The database name. Initial databases included with a HANA, express edition database are "SystemDB" and "HXE".
             The default value is "SystemDB".

  Actions
      -e, --enable
             Enable the transmission of telemetry data. Data will be transmitted after the next transmission interval.

      -b, --disable
             Disable the transmission of telemetry data. Data transmission will be disabled after the next transmission interval.

      -r, --report
             Report on the status of telemetry and the configuration for the database.

      -c, --churl
             Change the url of the telemetry server.
             The churl command also truncates the client transmission history for the database.

EXAMPLES
  Enable telemetry on the SystemDB database:
    $base_name -u system -p myPassword -d SystemDB -i 90 -e

  Enable telemetry on SystemDB. The script will prompt for the password:
    $base_name -u system -d SystemDB -i 90 -e

  Disable telemetry on the HXE tenant database:
    $base_name --user system --password myPassword --database HXE --instance 90 --disable

  Run the report on the HXE tenant database:
    $base_name --user system --password myPassword --database HXE --instance 90 --report

  Change the server url transmitted for the HXE tenant database:
    $base_name --user system --password myPassword --database HXE --instance 90 --churl "https://telemetry.cloud.sap"
EOF
}


############################################################################################
# Remove temp file
############################################################################################
remove_tmp_file() {
  rm -f ${out_tmp_file} >& /dev/null
}

############################################################################################
# Clean up temporary file and exit
############################################################################################
cleanup() {
  remove_tmp_file
}

############################################################################################
# HDB error handler
# HDB results and errors are written to the $out_tmp_File.
# The error message passed in is echoed out and then the contents of $out_tmp_file 
# are printed. Cleanup is then called and the program exited with an error code of 1
# arg1 - the error message
############################################################################################
handle_hdb_error() {
  echo
  echo "ERROR" 
  echo "$1"
  echo
  echo "DETAIL"
  cat ${out_tmp_file}
  echo
  cleanup
  exit 1
}

############################################################################################
# Non-HDB error handler
# Print the error that is passed in.
# arg1 - Error message that should be printed.
############################################################################################
handle_regular_error() {
  echo
  echo "ERROR" 
  echo "$1"
  echo
  cleanup
  exit 1
}

############################################################################################
# printTelemetryStatus
# Query the _SYS_TELEMETRY.TELEMETRY_INIFILE for the specified database and return the INI_VALUE.
# "yes" means enabled.
# "no" means it is not enabled.
############################################################################################
printTelemetryStatus() {
  cat <<-EOF

TELEMETRY CONFIGURATION
  Enabled:             $tc_telemetry_enabled
  License:             $tc_product_license
  Hardware Key:        $tc_hardware_key
  Server URL:          $tc_server_url
  Database:            $db_name


CLIENT TRANSMISSION HISTORY
  Client ID:           $client_client_id
  First Transmission:  $client_first_transmission
  Last Transmission:   $client_last_transmission
  Interval:            $client_interval

EOF
}

############################################################################################
# retrieveServerURL
# Query the _SYS_TELEMETRY.SERVER table for the server url.
# Sets the tc_server_url variable
############################################################################################
retrieveServerURL() {
  hdbsql -u $db_user -p $db_password -d $db_name -i $instance_number\
    "select SERVER_URL from _SYS_TELEMETRY.SERVER" > ${out_tmp_file} 2>&1
  #
  # A successful query will write the following result to the temporary out file if there have not yet been any transmissions.
  # 
    #  SERVER_URL  
    #  https://telemetry.cfapps.eu10.hana.ondemand.com
  #  1 row selected (overall time 797 usec; server time 178 usec)

  #If there is 1 row selected, then it is the most recent client transmission to the server
    query_result=`grep "1 row selected" ${out_tmp_file}`
  if [ -n "$query_result" ]; then
    tc_server_url=$(cat ${out_tmp_file} | awk '{ if ( NR==2 ) {print $1} }' | sed 's/\"//g')
  else
      #If we reach here then an error has been encountered in the query.
      errorMessage="Error encountered reading the _SYS_TELEMETRY.SERVER.SERVER_URL value."
    handle_hdb_error "$errorMessage"
  fi
}


############################################################################################
# retrieveMostRecentClientRow
# Query the _SYS_TELEMETRY.CLIENT table for the most recent entry.
# Sets the following variable values
#   client_client_id
#   client_first_transmission
#   client_last_transmission
#   interval
############################################################################################
retrieveMostRecentClientRow() {
  hdbsql -u $db_user -p $db_password -d $db_name -i $instance_number\
    "select top 1 CLIENT_ID, FIRST_TRANSMISSION_TIMESTAMP, LAST_TRANSMISSION_TIMESTAMP, TRANSMISSION_INTERVAL from _SYS_TELEMETRY.CLIENT order by first_transmission_timestamp desc " > ${out_tmp_file} 2>&1
  # A successful query will write the following result to the temporary out file if there have not yet been any transmissions.
  # 
  #  CLIENT_ID,FIRST_TRANSMISSION_TIMESTAMP,LAST_TRANSMISSION_TIMESTAMP,TRANSMISSION_INTERVAL
  #  0 rows selected (overall time 8493 usec; server time 123 usec)
  #
  # If there have been transactions a successful query will write the following result to the temporary out file:
  # 
  #  CLIENT_ID,FIRST_TRANSMISSION_TIMESTAMP,LAST_TRANSMISSION_TIMESTAMP,TRANSMISSION_INTERVAL
  #
  #  1 rows selected (overall time 8493 usec; server time 123 usec)  

  #If there is 1 row selected, then it is the most recent client transmission to the server
    query_result=`grep "1 row selected" ${out_tmp_file}`
  if [ -n "$query_result" ]; then
    client_client_id=$(cat ${out_tmp_file} | awk '{ FS=","; if ( NR==2 ) {print $1} }' | sed 's/\"//g')
    client_first_transmission=$(cat ${out_tmp_file} | awk '{ FS=","; if ( NR==2 ) {print $2} }' | sed 's/\"//g')
    client_last_transmission=$(cat ${out_tmp_file} | awk '{ FS=","; if ( NR==2 ) {print $3} }' | sed 's/\"//g')
    client_interval=$(cat ${out_tmp_file} | awk '{ FS=","; if ( NR==2 ) {print $4} }' | sed 's/\"//g')
  else
     #If there are 0 rows selected, then it is presumed that no transmissions have been sent yet. This is not an error condition.
       query_result=`grep "0 rows selected" ${out_tmp_file}`
     if [ -n "$query_result" ]; then
       client_client_id=""
     else
      #If we reach here then an error has been encountered in the query.
      errorMessage="Error encountered reading the _SYS_TELEMETRY.CLIENT table."
    handle_hdb_error "$errorMessage"
     fi
  fi
}


############################################################################################
# retrieveTelemetryStatus
# Query the _SYS_TELEMETRY.TELEMETRY_INIFILE for the specified database and return the INI_VALUE.
# "yes" means enabled.
# "no" means it is not enabled.
############################################################################################
retrieveTelemetryStatus() {
  hdbsql -u $db_user -p $db_password -d $db_name -i $instance_number\
    "select INI_VALUE from _SYS_TELEMETRY.TELEMETRY_INIFILE" > ${out_tmp_file} 2>&1
  #A successful query will write the following result to the temporary out file
  #   INI_VALUE
  #   "no"
  #   1 row selected (overall time 1449 usec; server time 866 usec)  
  query_result=`grep "1 row selected" ${out_tmp_file}`
  if [ -z "$query_result" ]; then
    handle_hdb_error "Failed to retrieve telemetry value from the ini file."
  fi
  #retrieve the value and strip the quotation marks
  tc_telemetry_enabled=$(cat ${out_tmp_file} | awk '{ if ( NR==2 ) {print $1} }' | sed 's/\"//g')
  if [ "$tc_telemetry_enabled" != "yes" ] && [ "$tc_telemetry_enabled" != "no" ]; then
      errorMessage="The INI_VALUE is invalid. It is \"$tc_telemetry_enabled\" but it should be \"yes\" or \"no\""
    handle_regular_error "$errorMessage"
  fi
}

############################################################################################
# retrieveLicenseHWKey
# Query the SYS.M_LICENSE view to see if this is a HXE license.
# A HXE license will have the product_name of SAP-HANA-DIGITAL
# Sets the following variables
#    tc_product_license
#    tc_hardware_key
############################################################################################
retrieveLicenseHWKey() {
  hdbsql -u $db_user -p $db_password -d $db_name -i $instance_number\
    "select PRODUCT_NAME, HARDWARE_KEY from SYS.M_LICENSE" > ${out_tmp_file} 2>&1
  #A successful query will write the following result to the temporary out file
  #   PRODUCT_NAME
  #   "SAP-HANA-DIGITAL"
  #   1 row selected (overall time 1449 usec; server time 866 usec)  
  
  #See if there was a database connection error.
  query_result=`egrep "[10] rows? selected" ${out_tmp_file}`
  if [ -z "$query_result" ]; then
    handle_hdb_error "Failed to connect to the database, $db_name. Check your connection settings."
  fi
  
  #Check if the user was able to connect but there is a problem with the product table or the user's level of access.
  #If the query below returns a result then they did not get any rows back.
  query_result=`egrep "0 rows selected" ${out_tmp_file}`
  if [ -n "$query_result" ]; then
    handle_hdb_error "No license retrieved. Make sure that the user, $db_user, has system table access privileges."
  fi  
  #retrieve the value and strip the quotation marks
  tc_product_license=$(cat ${out_tmp_file} | awk '{ FS=","; if ( NR==2 ) {print $1} }' | sed 's/\"//g')
  if [ "$tc_product_license" != "SAP-HANA-DIGITAL" ]; then
    errorMessage="Telemetry requires a license type of \"SAP-HANA-DIGITAL\". The database, $db_name, has a license of type \"$tc_product_license\"."
    handle_regular_error "$errorMessage"
  fi
  tc_hardware_key=$(cat ${out_tmp_file} | awk '{ FS=",";  if ( NR==2 ) {print $2} }' | sed 's/\"//g')
}


############################################################################################
# reportTelemetryStatus
# Print out the status report for telemetry.
############################################################################################
reportTelemetryStatus() {
  retrieveTelemetryStatus
  retrieveServerURL
  retrieveMostRecentClientRow
  printTelemetryStatus  
}

############################################################################################
# Set telemetry enabled
# Set the value of the telemetry enabled field in the global.ini file.
# arg1 Enabled value. [ "yes" | "no" ]
############################################################################################
setTelemetryEnabled() {
  hdbsql -u $db_user -p $db_password -d $db_name -i $instance_number\
    "alter system alter configuration ('global.ini', 'SYSTEM') SET ( 'telemetry', 'enabled' ) = '$1' with reconfigure" > ${out_tmp_file} 2>&1
  #A successful query will write the following result to the temporary out file
    #   0 rows affected (overall time 1449 usec; server time 866 usec)
    query_result=`grep "0 rows affected" ${out_tmp_file}`
  if [ -z "$query_result" ]; then
    handle_hdb_error "Failed to update the telemetry \"enabled\" setting."
  fi
  if [ "$1" == "yes" ]; then
    tmp_val="enabled"
  else
    tmp_val="disabled"
    fi   
  echo 
  echo Telemetry was successfully $tmp_val on the database, $db_name.
  echo
}

############################################################################################
# changeServerURL
# Changes the server URL and truncates the client table.
############################################################################################
changeServerURL() {
  # update the server url
  hdbsql -u $db_user -p $db_password -d $db_name -i $instance_number\
    "update _SYS_TELEMETRY.SERVER set SERVER_URL = '${tc_server_url}' " > ${out_tmp_file} 2>&1
  query_result=`grep "1 row affected" ${out_tmp_file}`
  if [ -z "$query_result" ]; then
    handle_hdb_error "Failed to update the server url."
  fi
  # Truncate the client table to avoid retransmitting with a stale client id.
  hdbsql -u $db_user -p $db_password -d $db_name -i $instance_number\
    "truncate table _SYS_TELEMETRY.CLIENT" > ${out_tmp_file} 2>&1
  query_result=`egrep "rows? affected" ${out_tmp_file}`
  if [ -z "$query_result" ]; then
    handle_hdb_error "Failed to truncate the client table. After addressing the error, you will need to rerun the \"churl\" command."
  fi
  echo 
  echo The Telemetry Server URL was successfully updated to ${tc_server_url} for the database, $db_name.
  echo
}

############################################################################################
# Validate that the user has hdbsql sql in the path
############################################################################################
validateHDBSQL() {
  which hdbsql > ${out_tmp_file} 2>&1
  which_result=`grep "no hdbsql in" ${out_tmp_file}`
  if [ -n "$which_result" ]; then
      errorMessage="The \"hdbsql\" command was not found. You must run this utility as a user that has \"hdbsql\" on its path."
    handle_hdb_error "$errorMessage"
  fi
}

############################################################################################
# Validate that the argument is not blank
# arg1 - The name of the argument
# arg2 - The argument value
############################################################################################
validateNotBlank() {
  if [ -z "$2" ]; then 
    errorMessage="$1 cannot be left blank."
  handle_regular_error "$errorMessage"
  fi
}

############################################################################################
# Validate the password. If the password is blank, prompt the user to enter the password.
#########################################################################################
validatePassword() {
   #prompt the user to enter the password if it is blank.
   if [ -z "$db_password" ]; then
     read -s -p "Enter the database user password: " db_password
     printf "\n"
   fi
   #If the database password is still blank, fail the execution.
   if [ -z "$db_password" ]; then
     errorMessage="Password cannot be left blank."
     handle_regular_error "$errorMessage"
   fi
}

############################################################################################
# validateServerURL
# Does a simple check for http at the beginning of the value.
#########################################################################################
validateServerURL() {
    urlRegEx='http'
    if [[ ! "${tc_server_url}" =~ "$urlRegEx" ]]; then
       handle_regular_error "The url ${tc_server_url} is not a valid url."  
    fi
}

############################################################################################
# Validate the connectivity options.
#########################################################################################
validateOptions() {
  validateNotBlank "User" $db_user
  validateNotBlank "Instance" $instance_number 
  validateNotBlank "Database" $db_name   
  validateNotBlank "Action" $action
  validatePassword
}

############################################################################################
# Check if tenant database started
#########################################################################################
isTenantDbStarted() {
  HDB info | grep -v grep | grep hdbindexserver >& /dev/null
}

############################################################################################
# Main
############################################################################################
base_name=`basename $0`
out_tmp_file="/tmp/out.$$"

#Initialize the command line arguments
db_user="SYSTEM"
db_password=""
instance_number="90"
db_name="SystemDB"
action=""

#Initialize the TELEMETRY CONFIGURATION variables
tc_telemetry_enabled=""
tc_product_license=""
tc_hardware_key=""
tc_server_url=""

#Initialize the CLIENT TRANSMISSION HISTORY variables
client_client_id=""
client_first_transmission=""
client_last_transmission=""
client_interval=""

#
# Parse argument
#
if [ $# -eq 0 ]; then
   usage
   exit 1
fi 

#Parse the options from the command line
if [ $# -gt 0 ]; then
  PARSED_OPTIONS=`getopt -n "$base_name" -a -o hebru:p:i:d:a:c: --long help,enable,disable,report,user:,password:,instance:,database:,churl: -- "$@"`
  if [ $? -ne 0 ]; then
    exit 1
  fi

  # Something has gone wrong with the getopt command
  if [ "$#" -eq 0 ]; then
    usage
    exit 1
  fi

  # Process command line arguments
  eval set -- "$PARSED_OPTIONS"
  while true
  do
    case "$1" in
    -h|--help)
      usage
      exit 0
      break;;
    -u|--user)
      db_user="$2"
      shift 2;;
    -p|--password)
      db_password="$2"
      shift 2;;
    -i|--instance)
      instance_number="$2"
      shift 2;;
    -d|--database)
      db_name="$2"
      shift 2;;
    -e|--enable)
      action="enable"
      shift 1;;
    -b|--disable)
      action="disable"
      shift 1;;
    -r|--report)
      action="report"
      shift 1;;
    -c|--churl)
      action="churl"
      tc_server_url=$2
      shift 2;;
    --)
      shift
      break;;
    *)
      echo "Invalid \"$1\" argument."
      usage
      exit 1
    esac
  done
fi

# Call 'cleanup' if Control-C or terminated
trap 'cleanup' SIGINT SIGTERM

# Validate the options selected for all but the "action" option
validateOptions

# Validate the user can execute hdbsql commands
validateHDBSQL

db_name_lc=`echo "${db_name}" | tr '[:upper:]' '[:lower:]'`
if [ "${db_name_lc}" != "systemdb" ]; then
  if ! isTenantDbStarted; then
    echo "Cannot perform action on \"$db_name\" database because it is started."
    exit 1
  fi
fi

# Make sure this is an HXE licensed database.
retrieveLicenseHWKey

#Execute the action 
case $action in
  report)
    reportTelemetryStatus
    ;;
  enable)
    setTelemetryEnabled "yes"
    ;;
  disable)
    setTelemetryEnabled "no"
    ;;
  churl)
    validateServerURL
    changeServerURL
    ;;
  *)
    handle_regular_error "$action is not a valid action."
    ;;
esac   

cleanup

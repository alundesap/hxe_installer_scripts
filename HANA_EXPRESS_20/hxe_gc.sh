#!/bin/bash

#
# This utility does garbage collection on HANA processes to free unused memory.
#

#
# Get SID from current user login <sid>adm
#
getSID() {
	local me=`whoami`
	if echo $me | grep 'adm$' >& /dev/null; then
		SID=`echo $me | cut -c1-3 | tr '[:lower:]' '[:upper:]'`
		if [ ! -d /hana/shared/${SID} ]; then
			echo "You login as \"$me\"; but SID \"${SID}\" (/hana/shared/${SID}) does not exist."
			exit 1
		fi
	else
		echo "You need to run this from HANA administrator user \"<sid>adm\"."
		exit 1
	fi
}

#
# Check what servers are installed and running
#
checkServer() {
	local hdbinfo_output=$(HDB info)
	if echo ${hdbinfo_output} | grep hdbnameserver >& /dev/null; then
		HAS_SERVER=1
		if echo ${hdbinfo_output} | grep "/hana/shared/${SID}/xs/router" >& /dev/null; then
			HAS_XSA=1
		fi
	else
		echo
		echo "Cannot find running HANA server.  Please start HANA with \"HDB start\" command."
		exit 1
	fi
}


# Prompt user password
# arg 1: user name
# arg 2: variable name to store password value
#
promptPwd() {
	local pwd=""
	while [ 1 ]; do
		read -r -s -p "Enter \"${1}\" password : " pwd
		if [ -z "$pwd" ]; then
			echo
			echo "Invalid empty password. Please re-enter."
			echo
		else
			break
		fi
	done
	eval $2=\$pwd

	echo
}

#
# Execute SQL statement and store output to SQL_OUTPUT
# $1 - instance #
# $2 - database
# $3 - user
# $4 - password
# $5 - SQL
execSQL() {
	local db="$2"
	local db_lc=`echo "$2" | tr '[:upper:]' '[:lower:]'`
	if [ "${db_lc}" == "systemdb" ]; then
		db="SystemDB"
	fi
	local sql="$5"
	SQL_OUTPUT=`/usr/sap/${SID}/HDB${1}/exe/hdbsql -a -x -i ${1} -d ${db} -u ${3} -p ${4} ${sql} 2>&1`
	if [ $? -ne 0 ]; then
		# Strip out password string
		if [ -n "${4}" ]; then
			sql=`echo "${sql}" | sed "s/${4}/********/g"`
		fi
		if [ -n "${SYSTEM_PWD}" ]; then
			sql=`echo "${sql}" | sed "s/${SYSTEM_PWD}/********/g"`
		fi
		echo "hdbsql $db => ${sql}"
		echo "${SQL_OUTPUT}"
		exit 1
	fi
}

collectGarbage() {
	local status=0
	echo "Collecting garbage..."

	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "select to_decimal(round(sum(exclusive_size_in_use)/1024/1024, 0)) as sum_exclusive_size_mb from m_heap_memory"
	local total_heap_before=`trim "${SQL_OUTPUT}"`
	local free_before=`/usr/bin/free -mh`

	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM RECLAIM VERSION SPACE"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM SAVEPOINT"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM CLEAR SQL PLAN CACHE"

	server_list="hdbnameserver hdbindexserver hdbcompileserver hdbpreprocessor hdbdiserver"
	if [ $HAS_XSA -eq 1 ]; then
		server_list="hdbnameserver hdbindexserver hdbcompileserver hdbpreprocessor hdbdiserver hdbwebdispatcher"
	fi
	hdbinfo_output=`HDB info`
	for server in $server_list; do
		if echo $hdbinfo_output | grep "${server}" >& /dev/null; then
			echo "Collect garbage on \"${server}\"..."
			output=`hdbcons -e ${server} "mm gc -f"`
			if [ $? -ne 0 ]; then
				echo "${output}"
				status=1
			fi
			echo "Shrink resource container memory on \"${server}\"..."
			output=`hdbcons -e ${server} "resman shrink"`
			if [ $? -ne 0 ]; then
				echo "${output}"
				status=1
			fi
		fi
	done

	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "select to_decimal(round(sum(exclusive_size_in_use)/1024/1024, 0)) as sum_exclusive_size_mb from m_heap_memory"
	local total_heap_after=`trim "${SQL_OUTPUT}"`
	local free_after=`/usr/bin/free -mh`

	echo
	echo "Total in use HANA processes heap memory (MB)"
	echo "============================================"
	echo "Before collection : $total_heap_before"
	echo "After  collection : $total_heap_after"

	echo
	echo "Free and used memory in the system"
	echo "=================================="
	echo "Before collection"
	echo "-------------------------------------------------------------------------"
	echo "$free_before"
	echo "After  collection"
	echo "-------------------------------------------------------------------------"
	echo "$free_after"
	echo

	return $status
}

# Trim leading and trailing spaces
trim() {
	trimmed="$1"
	trimmed=${trimmed%% }
	trimmed=${trimmed## }
	echo "$trimmed"
}

# Check if server user/password valid
# $1 - database
# $2 - user
# $3 - password
checkHDBUserPwd() {
	output=$(/usr/sap/${SID}/HDB${INSTANCE}/exe/hdbsql -a -x -quiet 2>&1 <<-EOF
\c -i ${INSTANCE} -d $1 -u $2 -p $3
EOF
)
	if [ $? -ne 0 ]; then
		echo
		echo "$output"
		echo
		echo "Cannot login to \"$1\" database with \"$2\" user."
		if echo "$output" | grep -i "authentication failed" >& /dev/null; then
			echo "Please check if password is correct."
			echo
			return 1
		else
			echo "Please check if the database is running."
			echo
			exit 1
		fi
	fi

	return 0
}

#########################################################
# Main
#########################################################
PROG_DIR="$(cd "$(dirname ${0})"; pwd)"
PROG_NAME=`basename $0`

SID="HXE"
INSTANCE="$TINSTANCE"
HAS_XSA=0

SYSTEM_PWD=""

getSID

checkServer

promptPwd "System database user (SYSTEM)" "SYSTEM_PWD"
while ! checkHDBUserPwd SystemDB SYSTEM ${SYSTEM_PWD}; do
	promptPwd "System database user (SYSTEM)" "SYSTEM_PWD"
done

echo

collectGarbage

#!/bin/bash

#
# This utility upgrades HANA, express edition 2.0 and newer to current version.
#

checkRootUser() {
	if [ ${EUID} -ne 0 ]; then
		echo "You need to run \"${PROG_NAME}\" as root."
		exit 1
	fi
}

# Prompt HANA, express edition installer image root directory
promptImageRootDir() {
	# Check default location has valid image
	if [ ! -f "${IMAGE_DIR}/${DATA_UNITS_DIR}/${HDB_LCM_COMP_DIR}/hdblcm" ]; then
		IMAGE_DIR=""
	fi

	echo "Enter HANA, express edition installer root directory:"
	echo "    Hint: <extracted_path>/${HXE_DIR}"
	while [ 1 ]; do
		read -p "HANA, express edition installer root directory [${IMAGE_DIR}]: " tmp
		if [ -z "${tmp}" -a -n "${IMAGE_DIR}" ]; then
			break
		elif [ -z "${tmp}" ]; then
			continue
		else
			if [ ! -e "${tmp}" ]; then
				echo
				echo "\"${tmp}\" does not exist or not a directory."
				echo
			elif [ ! -f "${tmp}/${DATA_UNITS_DIR}/${HDB_LCM_COMP_DIR}/hdblcm" ]; then
				echo
				echo "\"${tmp}\" does not contain HANA, express edition installer."
				echo "Life cycle management utility \"${tmp}/DATA_UNITS/${HDB_LCM_COMP_DIR}/hdblcm\" does not exist."
				echo
			else
				IMAGE_DIR="${tmp}"
				break
			fi
		fi
	done

	if [ -d "${IMAGE_DIR}/${DATA_UNITS_DIR}/${XSA_RT_COMP_DIR}" ]; then
		IMAGE_HAS_XSA=1
	fi
}

#
# Prompt HANA system ID
#
promptSID() {
	while [ 1 ]; do
		read -p "Enter SAP HANA system ID [${SID}]: " id
		if [ -z "${id}" -a -n "${SID}" ]; then
			break
		else
			if [[ ${id} =~ ^[A-Z][A-Z,0-9][A-Z,0-9]$ ]]; then
				SID="${id}"
				break
			else
				echo ""
				echo "Invalid SAP HANA system ID.  This must be a three characters string."
				echo "First character has to be an upper case letter."
				echo "Second and third characters can be upper case letter or a decimal digit."
				echo ""
			fi
                fi
        done

	SYSTEM_ADMIN=`echo ${SID}adm | tr '[:upper:]' '[:lower:]'`
}

#
# Check what servers are installed and running
#
checkServer() {
	count=`su -l ${SYSTEM_ADMIN} -c "HDB info | grep hdbnameserver | wc -l"`
	if [ "$count" -gt "2" ]; then
		HAS_SERVER=1
		count=`su -l ${SYSTEM_ADMIN} -c "HDB info | grep \"/hana/shared/${SID}/xs/router\" | wc -l"`
		if [ "$count" -gt "2" ]; then
			HAS_XSA=1
		fi
	else
		echo
		echo "Cannot find running HANA server.  Please start HANA with \"HDB start\" command."
		exit 1
	fi

	OLD_VERSION=`su -l ${SYSTEM_ADMIN} -c "HDB version | grep '^  version' | awk '{print \\$2}'"`
	if [[ ! "$OLD_VERSION" =~ ^2\.00 ]]; then
		echo
		echo "$PROG_NAME only supports upgrade from HDB version 2.00 and newer."
		echo "You have HDB version $OLD_VERSION."
		exit 1
	fi
}

#
# Check if this XSC image
#
checkXSC() {
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM _SYS_REPO.DELIVERY_UNITS"
	SQL_OUTPUT=`trim ${SQL_OUTPUT}`
	if [ $SQL_OUTPUT -gt 0 -a $HAS_XSA -ne 1 ]; then
		HAS_XSC=1
	fi
}

#
# Check if tenant database exits
hasDatabase() {
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) from \"PUBLIC\".\"M_DATABASES\" WHERE DATABASE_NAME='${1}'"
	SQL_OUTPUT=`trim ${SQL_OUTPUT}`
	if [ "${SQL_OUTPUT}" == "1" ]; then
		return 0
	fi

	return 1
}

#
# Prompt instance number
#
promptInstanceNumber() {
	local num=""
	if [ ! -d "/hana/shared/${SID}/HDB${INSTANCE}" ]; then
		INSTANCE=""
		for i in /hana/shared/${SID}/HDB?? ; do
			num=`echo "$i" | cut -c21-22`
			if [[ ${num} =~ ^[0-9]+$ ]] ; then
				INSTANCE="$num"
				break
			fi
		done
	fi

	while [ 1 ]; do
		read -p "Enter HANA instance number [${INSTANCE}]: " num

		if [ -z "${num}" ]; then
			if [ -z "${INSTANCE}" ]; then
				continue
			else
				num="${INSTANCE}"
			fi
		fi

		if ! [[ ${num} =~ ^[0-9]+$ ]] ; then
			echo
			echo "\"$num\" is not a number.  Enter a number between 00 and 99."
			echo
			continue
		elif [ ${num} -ge 0 -a ${num} -le 99 ]; then
			if [[ ${num} =~ ^[0-9]$ ]] ; then
				num="0${num}"
			fi

			if [ ! -d "/hana/shared/${SID}/HDB${num}" ]; then
				echo
				echo "Instance ${num} does not exist in SID \"$SID\" (/hana/shared/${SID}/HDB${num})."
				echo
				continue
			else
				INSTANCE="${num}"
				break
			fi
		else
			echo
			echo "Invalid number.  Enter a number between 00 and 99."
			echo
			continue
		fi
	done
}


# Prompt user password
# arg 1: user name
# arg 2: variable name to store password value
#
promptPwd() {
	local pwd=""
	while [ 1 ]; do
		read -s -p "Enter \"${1}\" password : " pwd
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
	local sql="$5"

	if [ "${db_lc}" == "systemdb" ]; then
		db="SystemDB"
	fi

	SQL_OUTPUT=`su -l ${SYSTEM_ADMIN} -c "\"/usr/sap/${SID}/HDB${1}/exe/hdbsql\" -a -x -i ${1} -d ${db} -u ${3} -p \"${4}\" \"${sql}\" 2>&1"`
	if [ $? -ne 0 ]; then
		# Strip out password string
		if [ -n "${4}" ]; then
			sql=`echo "${sql}" | sed "s/${4}/********/g"`
		fi
		if [ -n "${SYSTEM_PWD}" ]; then
			sql=`echo "${sql}" | sed "s/${SYSTEM_PWD}/********/g"`
		fi
		if [ -n "${XSA_ADMIN_PWD}" ]; then
			sql=`echo "${sql}" | sed "s/${XSA_ADMIN_PWD}/********/g"`
		fi
		echo "hdbsql $db => ${sql}"
		echo "${SQL_OUTPUT}"
		exit 1
	fi
}

#
# Print pre-upgrade summary
#
printSummary() {
	echo
	echo "##############################################################################"
	echo "# Summary before execution                                                   #"
	echo "##############################################################################"
	echo "HANA, express edition installer : ${IMAGE_DIR}"
	echo "  HANA system ID                : ${SID}"
	echo "  HANA instance number          : ${INSTANCE}"
	echo "  Log file                      : ${LOG_FILE}"
	if [ $HAS_XSA -eq 1 ]; then
		echo "  XS Advanced Components        : all"
	fi

	echo

	while [ 1 ] ; do
		read -p "Proceed with upgrade? (Y/N) : " proceed
		if [ "${proceed}" == "Y" -o "${proceed}" == "y" ]; then
			echo
			return
		elif [ "${proceed}" == "N" -o "${proceed}" == "n" ]; then
			exit 1
		fi
	done
}


upgradeHXE() {
	local status=0
	echo "Upgrade HANA, express edition..."
	local log_begin=`wc -l $LOG_FILE | cut -d' ' -f1`

	"${IMAGE_DIR}/${DATA_UNITS_DIR}/${HDB_SERVER_COMP_DIR}/hdblcm" -s ${SID} --action=update --read_password_from_stdin=xml -b <<-EOF
<?xml version="1.0" encoding="UTF-8"?><Passwords><password><![CDATA[${SYSTEM_ADMIN_PWD}]]></password><system_user_password><![CDATA[${SYSTEM_PWD}]]></system_user_password><sapadm_password><![CDATA[${SYSTEM_ADMIN_PWD}]]></sapadm_password><org_manager_password><![CDATA[${XSA_ADMIN_PWD}]]></org_manager_password></Passwords>
EOF
	status=$?
	local log_end=`wc -l $LOG_FILE | cut -d' ' -f1`
	if [ $status -ne 0 ] || sed -n "${log_begin},${log_end}p" $LOG_FILE | grep -i "fail\|error\|cannot find\|No such file\|is invalid" >& /dev/null; then
		echo "Upgrade failed."
		exit 1
	fi
}

postProcessServer() {

	# Include diserver in startup for server-only
	if [ $HAS_XSA -eq 0 ]; then
		# SAP_RETRIEVAL_PATH=/hana/shared/${SID}/HDB${INSTANCE}/hxehost
		if ! grep '^\[diserver\]' $SAP_RETRIEVAL_PATH/daemon.ini >& /dev/null; then
			cat >> ${SAP_RETRIEVAL_PATH}/daemon.ini <<-EOF

[diserver]
instances = 1
EOF
		fi
	fi

	# Copy change_key.sh to <hxeadm home>/bin directory
	su -l ${SYSTEM_ADMIN} -c "mkdir -p /usr/sap/${SID}/home/bin"
	su -l ${SYSTEM_ADMIN} -c "cp -p ${IMAGE_DIR}/change_key.sh /usr/sap/${SID}/home/bin"
	su -l ${SYSTEM_ADMIN} -c "chmod 755 /usr/sap/${SID}/home/bin/change_key.sh"

	# Copy hxe_gc.sh to <hxeadm home>/bin directory
        su -l ${SYSTEM_ADMIN} -c "mkdir -p /usr/sap/${SID}/home/bin"
        su -l ${SYSTEM_ADMIN} -c "cp -p ${IMAGE_DIR}/hxe_gc.sh /usr/sap/${SID}/home/bin"
        su -l ${SYSTEM_ADMIN} -c "chmod 755 /usr/sap/${SID}/home/bin/hxe_gc.sh"
}

startTenantDB() {
	if [ $HAS_TENANT_DB -eq 1 ]; then
		echo "Start \"${SID}\" tenant database. This may take a while..."
		execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM START DATABASE ${SID}"
	fi
}

#
# Install XSC
#
installXSC() {
	echo "Importing delivery units..."
	"/hana/shared/${SID}/global/hdb/install/bin/hdbupdrep" --content_directory="/hana/shared/${SID}/global/hdb/auto_content" --read_password_from_stdin=xml -b <<-EOF
<?xml version="1.0" encoding="UTF-8"?><Passwords><password><![CDATA[${SYSTEM_PWD}]]></password><system_user_password><![CDATA[${SYSTEM_PWD}]]></system_user_password></Passwords>
EOF
	if [ $? -ne 0 ]; then
	echo
		echo "Failed to import delivery units."
		exit 1
	fi

	"/hana/shared/${SID}/global/hdb/install/bin/hdbupdrep" --content_directory="/hana/shared/${SID}/global/hdb/auto_content/systemdb" --read_password_from_stdin=xml -b <<-EOF
<?xml version="1.0" encoding="UTF-8"?><Passwords><password><![CDATA[${SYSTEM_PWD}]]></password><system_user_password><![CDATA[${SYSTEM_PWD}]]></system_user_password></Passwords>
EOF
	if [ $? -ne 0 ]; then
		echo
		echo "Failed to import delivery units."
		exit 1
	fi

	echo "Enable statistics server..."
	execSQL ${INSTANCE} SystemDB ${SYSTEM_USER} ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini','SYSTEM') SET ('statisticsserver','active') = 'true' WITH RECONFIGURE"
}

#
# Grant activated role
#
grantActivatedRole() {
	local role_name=""
	local retry=300
	local granted=0
	local role_list=(
		sap.hana.ide.roles::EditorDeveloper
		sap.hana.ide.roles::CatalogDeveloper
		sap.hana.ide.roles::SecurityAdmin
		sap.hana.ide.roles::TraceViewer
		sap.hana.xs.admin.roles::HTTPDestViewer
		sap.hana.xs.admin.roles::SQLCCAdministrator
		sap.hana.xs.debugger::Debugger
	)

	if [ $HAS_XSA -eq 1 -o $HAS_XSC -eq 1 ]; then
		for role_name in "${role_list[@]}"; do
			echo "Grant activated role \"${role_name}\" to SYSTEM on SystemDB database..."
			retry=300
			granted=0
			while [ $retry -gt 0 ]; do
				execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM ROLES WHERE ROLE_NAME='${role_name}'"
				SQL_OUTPUT=`trim ${SQL_OUTPUT}`
				if [ "$SQL_OUTPUT" == "1" ]; then
					execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
					granted=1
					break
				fi
				sleep 10s
				retry=$(($retry - 10))
			done
			if [ $granted -eq 0 ]; then
				echo
				echo "Warning: Waiting for activated role \"${role_name}\" to be available has timed out."
				echo "Please execute this command manually in SystemDB database:"
				echo "	CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
				echo
			fi
		done

		if [ $HAS_TENANT_DB -eq 1 ]; then
			for role_name in "${role_list[@]}"; do
				echo "Grant activated role \"${role_name}\" to SYSTEM on ${SID} database..."
				retry=300
				granted=0
				while [ $retry -gt 0 ]; do
					execSQL ${INSTANCE} ${SID} SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM ROLES WHERE ROLE_NAME='${role_name}'"
					SQL_OUTPUT=`trim ${SQL_OUTPUT}`
					if [ "$SQL_OUTPUT" == "1" ]; then
						execSQL ${INSTANCE} ${SID} SYSTEM ${SYSTEM_PWD} "CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
						granted=1
						break
					fi
					sleep 10s
					retry=$(($retry - 10))
				done
				if [ $granted -eq 0 ]; then
					echo
					echo "Warning: Waiting for activated role \"${role_name}\" to be available has timed out."
					echo "Please execute this command manually in ${SID} database:"
					echo "	CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
					echo
				fi
			done
		fi

		echo "Set system configuration wdisp/system_auto_configuration=true in webdispatcher.ini..."
		execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('webdispatcher.ini', 'system') SET('profile', 'wdisp/system_auto_configuration') = 'true' WITH RECONFIGURE;"
	fi
}

postProcessXSA() {
	if [ $HAS_XSA -ne 1 ]; then
		return
	fi

	# Reduce memory footprint by storing all lob data on disk
	echo "Reduce memory footprint by storing all lob data on disk..."
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER TABLE \\\"SYS_XS_RUNTIME\\\".\\\"BLOBSTORE\\\" ALTER (\\\"VALUE\\\" BLOB MEMORY THRESHOLD 0)"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memoryobjects', 'unload_upper_bound') = '838860800' with reconfigure"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memoryobjects', 'unused_retention_period' ) = '60' with reconfigure"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memoryobjects', 'unused_retention_period_check_interval' ) = '60' with reconfigure"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memorymanager', 'gc_unused_memory_threshold_abs' ) = '1024' with reconfigure"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "DROP FULLTEXT INDEX _sys_repo.\\\"FTI_ACTIVE_OBJECT_CDATA\\\""
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "CREATE FULLTEXT INDEX _sys_repo.\\\"FTI_ACTIVE_OBJECT_CDATA\\\" ON \\\"_SYS_REPO\\\".\\\"ACTIVE_OBJECT\\\"(\\\"CDATA\\\" ) LANGUAGE DETECTION ('EN') ASYNC PHRASE INDEX RATIO 0.0 SEARCH ONLY OFF FAST PREPROCESS OFF TOKEN SEPARATORS '/;,.:-_()[]<>!?*@+{}=\\\"&#\$~|'"

	# Enable repository
	echo "Enable repository..."
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM') SET ('repository', 'enable_repository') = 'TRUE' WITH RECONFIGURE"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini', 'SYSTEM') SET ('repository', 'enable_repository') = 'TRUE'  WITH RECONFIGURE"

	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini', 'SYSTEM') SET ('session', 'idle_connection_timeout') = '60' WITH RECONFIGURE;"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM') SET ('session', 'idle_connection_timeout') = '60' WITH RECONFIGURE;"

	echo "Login to XSA services..."
	output=`su -l ${SYSTEM_ADMIN} -c "xs login -u xsa_admin -p \"${XSA_ADMIN_PWD}\" -s $SPACE_NAME"`
	if [ $? -ne 0 ]; then
		echo "${output}"
		echo
		echo "Cannot login to XSA services.  Please check HANA has started and login/password are correct."
		exit 1
	fi

	# Stop apps
	stopApps

    	#Cleanup extra app instances
	cleanupApps

	# Copy create_tenantdb.sh to <hxeadm home>/bin directory
	su -l ${SYSTEM_ADMIN} -c "mkdir -p /usr/sap/${SID}/home/bin"
	su -l ${SYSTEM_ADMIN} -c "cp -p ${IMAGE_DIR}/create_tenantdb.sh /usr/sap/${SID}/home/bin"
	su -l ${SYSTEM_ADMIN} -c "chmod 755 /usr/sap/${SID}/home/bin/create_tenantdb.sh"

	# Copy hxe_telemetry.sh to <hxeadm home>/bin directory
	su -l ${SYSTEM_ADMIN} -c "cp -p ${IMAGE_DIR}/hxe_telemetry.sh /usr/sap/${SID}/home/bin"
	su -l ${SYSTEM_ADMIN} -c "chmod 755 /usr/sap/${SID}/home/bin/hxe_telemetry.sh"

	# Copy register_cockpit.sh to <hxeadm home>/bin directory
	su -l ${SYSTEM_ADMIN} -c "cp -p ${IMAGE_DIR}/register_cockpit.sh /usr/sap/${SID}/home/bin"
	su -l ${SYSTEM_ADMIN} -c "chmod 755 /usr/sap/${SID}/home/bin/register_cockpit.sh"
}

#
# Cycle through the services of an MTA and either stop them or start them
# Note: need "action" variable defined
#
processMTA() {
	rowNum=0
	startAppsRowNum=9999999
	while read row; do
		appName=`echo $row | cut -d' ' -f1`
		if [ "$rowNum" -ge "$startAppsRowNum" ]; then
			if [ -n "$appName" ] ; then
				if [ "$action" == "stop" ]; then
					echo "Stopping ${appName}..."
				else
					echo "Starting ${appName}..."
				fi
				output=`su -l ${SYSTEM_ADMIN} -c "xs $action $appName"`
				if [ $? -ne 0 ]; then
					echo "${output}"
					exit 1
				fi
			else
				#if the $appName variable is blank we have reached the end of the app section
				#This happens because there is a Services section after the Apps: section
				break
			fi
		else
			if [ "$appName" == "Apps:" ]; then
				startAppsRowNum=$(($rowNum+3))
			fi
		fi
		rowNum=$(($rowNum + 1))
	done
}

#
# Cleanup apps
# This function removes any apps that crashed or instances of apps that were started.
#
cleanupApps() {
	echo "Cleanup stopped applications..."

	# Get apps
	local apps=`su -l hxeadm -c "xs apps | awk '{if ((NR>6) && (length(\\$0) > 1)) {print \\$1}}'"`
	for appName in $apps; do
		echo "Cleaning up instances of $appName pass 1..."
		#Clean up the crashed instances
		output=`su -l ${SYSTEM_ADMIN} -c "xs delete-app-instances $appName --crashed -f"`
		if [ $? -ne 0 ]; then
			echo "${output}"
			echo
			echo "Failed to delete crashed instances for $appName."
			exit 1
		fi

		#Clean up the stopped instances
		echo "Cleaning up stopped instances of $appName pass 2..."
		output=`su -l ${SYSTEM_ADMIN} -c "xs delete-app-instances $appName --stopped -f"`
		if [ $? -ne 0 ]; then
			echo "${output}"
			echo
			echo "Failed to delete stopped instances for $appName."
			exit 1
		fi
	done
}

#
# Stop apps
# This function turns off a few mtas to free up some memory for HXE to run.
stopApps() {
	# "stop" or "start" apps
	action=stop

	echo "Stop applications..."

	#stop all the apps for jobscheduler
	su -l ${SYSTEM_ADMIN} -c "xs mta com.sap.xs.jobscheduler" | processMTA

	#stop all the apps for devx
#	xs mta com.sap.devx.webide | processMTA
#	xs mta com.sap.devx.di.builder | processMTA

	echo "Stopping di-cert-admin-ui..."
	output=`su -l ${SYSTEM_ADMIN} -c "xs stop di-cert-admin-ui"`
	if [ $? -ne 0 ]; then
		echo "${output}"
		exit 1
	fi

	echo "Stopping di-space-enablement-ui..."
	output=`su -l ${SYSTEM_ADMIN} -c "xs stop di-space-enablement-ui"`
	if [ $? -ne 0 ]; then
		echo "${output}"
		exit 1
	fi

#	echo "Stopping sap-portal-services..."
#	output=`xs stop sap-portal-services`
#	if [ $? -ne 0 ]; then
#		echo "${output}"
#		exit 1
#	fi
}

#
# Remove uneeded files
#
removePostInstallFiles() {
	# remove tomcat war files
	rm -f /hana/shared/${SID}/xs/uaaserver/tomcat/webapps/hdi-broker.war
	rm -f /hana/shared/${SID}/xs/uaaserver/tomcat/webapps/sapui5.war
	rm -f /hana/shared/${SID}/xs/uaaserver/tomcat/webapps/uaa-security.war

	# Delete the DataQuality directory
	if [ "$PLATFORM" == "LINUX_X86_64" ]; then
		rm -rf /hana/shared/${SID}/exe/linuxx86_64/HDB*/DataQuality
	else
		rm -rf /hana/shared/${SID}/exe/linuxppc64le/HDB*/DataQuality
	fi
}

collectGarbage() {
	echo "Do garbage collection..."

	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM RECLAIM VERSION SPACE"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM SAVEPOINT"
	execSQL ${INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM CLEAR SQL PLAN CACHE"

	server_list="hdbnameserver hdbindexserver hdbcompileserver hdbpreprocessor hdbdiserver"
	if [ $HAS_XSA -eq 1 ]; then
		server_list="hdbnameserver hdbindexserver hdbcompileserver hdbpreprocessor hdbdiserver hdbwebdispatcher"
	fi
	hdbinfo_output=`su -l ${SYSTEM_ADMIN} -c "HDB info"`
	for server in $server_list; do
		if echo $hdbinfo_output | grep "${server}" >& /dev/null; then
			echo "Collect garbage on \"${server}\"..."
			output=`su -l ${SYSTEM_ADMIN} -c "/usr/sap/${SID}/HDB${INSTANCE}/exe/hdbcons -e ${server} \"mm gc -f\""`
			if [ $? -ne 0 ]; then
				echo "${output}"
			fi
			echo "Shrink resource container memory on \"${server}\"..."
			output=`su -l ${SYSTEM_ADMIN} -c "/usr/sap/${SID}/HDB${INSTANCE}/exe/hdbcons -e ${server} \"resman shrink\""`
			if [ $? -ne 0 ]; then
				echo "${output}"
			fi
		fi
	done

	echo "Reclaim data volume..."
	output=`su -l ${SYSTEM_ADMIN} -c "/usr/sap/${SID}/HDB${INSTANCE}/exe/hdbcons -e hdbnameserver \"dvol reclaim -o 105\""`
	if echo "$output" | grep -i error >& /dev/null; then
		echo "${output}"
		exit 1
	fi

	echo "Release free log segments..."
	output=`su -l ${SYSTEM_ADMIN} -c "/usr/sap/${SID}/HDB${INSTANCE}/exe/hdbcons -e hdbnameserver \"log release\""`
	if echo "$output" | grep -i error >& /dev/null; then
		echo "${output}"
		exit 1
	fi
}

# Trim leading and trailing spaces
trim()
{
	trimmed="$1"
	trimmed=${trimmed%% }
	trimmed=${trimmed## }
	echo "$trimmed"
}

#
# Check local OS user password
# $1 - user/login name
# $2 - password
checkLocalOSUserPwd() {
	local user=$1
	local passwd=$2

	local shadow_hash=$(grep "^$user" /etc/shadow | cut -d':' -f2)
	if [ -n "$shadow_hash" ]; then
		local algo=$(echo $shadow_hash | cut -d'$' -f2)
		local salt=$(echo $shadow_hash | cut -d'$' -f3)
		local allsalt="\$${algo}\$${salt}\$"
		local genpass=`python <<EOF
import crypt,sys
print crypt.crypt("$passwd", "$allsalt")
EOF`
		if [ "$genpass" == "$shadow_hash" ]; then
			return 0
		else
			echo
			echo "Invalid password."
			echo
		fi
	else
		echo
		echo "User \"$user\" does not exist."
		echo
	fi
	return 1
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

updateVersionFile() {
	rm -f /usr/sap/${SID}/home/hxe_version.txt

	local install_type=""
	if [ -f /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt ]; then
		install_type=$(grep ^INSTALL_TYPE /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt | cut -d'=' -f2)
		rm -f /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt
	fi

	# Copy hxe_info.txt to /usr/sap/<SID>/SYS/global/hdb directory
	su -l ${SYSTEM_ADMIN} -c "cp -p ${IMAGE_DIR}/hxe_info.txt /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt"
	su -l ${SYSTEM_ADMIN} -c "chmod 644 /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt"

	sed -i "s/^INSTALL_TYPE*=.*/INSTALL_TYPE=$install_type/" /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt

	local install_date=`date --utc`
	sed -i "s/^INSTALL_DATE.*=.*/INSTALL_DATE=$install_date/" /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt

	if [ $HAS_XSA -ne 1 ]; then
		sed -i "/^XSA/d" /usr/sap/${SID}/SYS/global/hdb/hxe_info.txt
	fi
}

#########################################################
# Main
#########################################################
PROG_DIR="$(cd "$(dirname ${0})"; pwd)"
PROG_NAME=`basename $0`

PLATFORM=""
os=`uname -o | tr '[:upper:]' '[:lower:]'`
machine=`uname -m | tr '[:upper:]' '[:lower:]'`
if [[ "$os" =~ linux ]]; then
	if [ "$machine" == "x86_64" ] || [ "$machine" == "amd64" ] || [ "$machine" == "i386" ] || [ "$machine" == "i686" ]; then
		PLATFORM="LINUX_X86_64"
	elif [ "$machine" == "ppc64le" ]; then
		PLATFORM="LINUX_PPC64LE"
	fi
fi
IMAGE_DIR="$PROG_DIR"
HXE_DIR="HANA_EXPRESS_20"
DATA_UNITS_DIR="DATA_UNITS"
HDB_SERVER_COMP_DIR="HDB_SERVER_${PLATFORM}"
HDB_LCM_COMP_DIR="HDB_LCM_${PLATFORM}"
XSA_RT_COMP_DIR="XSA_RT_10_${PLATFORM}"
XSA_CONTENT_COMP_DIR="XSA_CONTENT_10"
HANA_COCKPIT_COMP_DIR="HANA_COCKPIT_20"
WEB_IDE_COMP_DIR="XSAC_SAP_WEB_IDE_20"
SA_DIR="HANA_STREAMING_4H20_01_HXE"
IMAGE_HAS_XSA=0
OLD_VERSION=""

HAS_SERVER=0
HAS_XSC=0
HAS_XSA=0
SID="HXE"
INSTANCE="90"

HAS_TENANT_DB=0

SYSTEM_ADMIN="hxeadm"
SYSTEM_ADMIN_PWD=""
SYSTEM_USER="SYSTEM"
SYSTEM_PWD=""
XSA_ADMIN_PWD=""

SPACE_NAME="SAP"

DATE=$(date +"%Y-%m-%d_%H.%M.%S")
LOG_FILE="/var/tmp/hxe_upgrade_${DATE}.log"

if [ "$PLATFORM" != "LINUX_X86_64" ] && [ -d "${IMAGE_DIR}/${DATA_UNITS_DIR}/HDB_LCM_LINUX_X86_64" ]; then
	echo "Invalid platform.  This is HANA, express edition on Linux X86_64"
	exit 1;
elif [ "$PLATFORM" != "LINUX_PPC64LE" ] && [ -d "${IMAGE_DIR}/${DATA_UNITS_DIR}/HDB_LCM_LINUX_PPC64LE" ]; then
	echo "Invalid platform.  This is HANA, express edition on Linux PowerPC 64-bit (little endian)."
	exit 1;
fi

checkRootUser

# Capture output to log
if [ -f $LOG_FILE ]; then
	rm -f $LOG_FILE
fi
touch $LOG_FILE
chmod 640 $LOG_FILE
date +"%Y-%m-%d %H.%M.%S :" >> $LOG_FILE
echo "" >> $LOG_FILE

promptImageRootDir

promptSID

promptInstanceNumber

checkServer

if [ $HAS_XSA -eq 1 -a $IMAGE_HAS_XSA -ne 1 ]; then
	echo
	echo "Cannot do upgrade.  Your installation has XS Advanced components.  However, the HANA, express edition image in "${IMAGE_DIR}" does not." | fold -w 80 -s
	echo
	echo "Please download and extract hxexsa.tgz to `dirname ${IMAGE_DIR}`." | fold -w 80 -s
	echo
	exit 1
fi

promptPwd "System administrator (${SYSTEM_ADMIN})" "SYSTEM_ADMIN_PWD"
while ! checkLocalOSUserPwd  ${SYSTEM_ADMIN} ${SYSTEM_ADMIN_PWD}; do
	promptPwd "System administrator (${SYSTEM_ADMIN})" "SYSTEM_ADMIN_PWD"
done

promptPwd "System database user (SYSTEM)" "SYSTEM_PWD"
while ! checkHDBUserPwd SystemDB SYSTEM ${SYSTEM_PWD}; do
	promptPwd "System database user (SYSTEM)" "SYSTEM_PWD"
done


if [ $HAS_XSA -eq 1 ]; then
	promptPwd "XSA administrative user (XSA_ADMIN)" "XSA_ADMIN_PWD"
	while ! checkHDBUserPwd SystemDB XSA_ADMIN ${XSA_ADMIN_PWD}; do
		promptPwd "System database user (XSA_ADMIN)" "XSA_ADMIN_PWD"
	done
fi

printSummary >& >(tee -a "$LOG_FILE")

# Capture setup output to log file
exec 0>&-
exec >& >( awk -v lfile="$LOG_FILE" '{ print $0; print strftime("%Y-%m-%d %H:%M:%S :"),$0 >> (lfile); fflush() }' )

echo

upgradeHXE

installXSC

checkXSC

if hasDatabase ${SID}; then
	HAS_TENANT_DB=1
fi

startTenantDB

postProcessServer

postProcessXSA

grantActivatedRole

removePostInstallFiles

echo "Restarting HDB..."
output=`su -l ${SYSTEM_ADMIN} -c "HDB stop"`
if [ $? -ne 0 ]; then
	echo "$output"
	echo "Failed to stop HDB."
	exit 1
fi
output=`su -l ${SYSTEM_ADMIN} -c "HDB start"`
if [ $? -ne 0 ]; then
	echo "$output"
	echo "Failed to start HDB."
	exit 1
fi

collectGarbage

updateVersionFile

echo "HDB is successfully upgraded."

#!/bin/bash


#########################################################
# Print usage
#########################################################
usage() {
cat <<-EOF
This script is to change security keys for HANA system.

Usage:"
   $base_name [<options>]

   Options:
   -h                         Print this help
   -d                         Tenant database.  Default is <SID>.

EOF
}

#########################################################
# Get SID from current user login <sid>adm
#########################################################
getSID() {
	me=`whoami`
	if echo $me | grep 'adm$' >& /dev/null; then
		sid=`echo $me | cut -c1-3 | tr '[:lower:]' '[:upper:]'`
		if [ ! -d /hana/shared/${sid} ]; then
			echo
			echo "You login as \"$me\"; but SID \"${sid}\" (/hana/shared/${sid}) does not exist."
			exit 1
		fi
	else
		echo
		echo "You need to run this from HANA administrator user \"<sid>adm\"."
		exit 1
	fi
}

#########################################################
# Prompt instance number
#########################################################
promptInstanceNumber() {
	local num=""
	if [ ! -d "/hana/shared/${sid}/HDB${instance_number}" ]; then
		instance_number=""
		for i in /hana/shared/${sid}/HDB?? ; do
			num=`echo "$i" | cut -c21-22`
			if [[ ${num} =~ ^[0-9]+$ ]] ; then
				instance_number="$num"
				break
			fi
		done
	fi

	while [ 1 ]; do
		read -p "Enter HANA instance number [${instance_number}]: " num

		if [ -z "${num}" ]; then
			if [ -z "${instance_number}" ]; then
				continue
			else
				num="${instance_number}"
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

			if [ ! -d "/hana/shared/${sid}/HDB${num}" ]; then
				echo
				echo "Instance ${num} does not exist in SID \"$sid\" (/hana/shared/${sid}/HDB${num})."
				echo
				continue
			else
				instance_number="${num}"
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

#########################################################
# Prompt password
#########################################################
# arg 1: Description
# arg 2: Variable name to store password value
#
promptPwd() {
	local pwd=""
	read -r -s -p "Enter ${1} password: " pwd
	eval $2=\$pwd

	echo
}


#########################################################
# Change Secure Store in File System master keys
#########################################################
changeSSFSKeys() {
	echo "Re-encrypt master key of the instance SSFS..."
	export RSEC_SSFS_DATAPATH=/usr/sap/$sid/SYS/global/hdb/security/ssfs
	export RSEC_SSFS_KEYPATH=/usr/sap/$sid/SYS/global/hdb/security/ssfs
	rsecssfx changekey $(rsecssfx generatekey -getPlainValueToConsole)
	echo

	echo "Add new entry to global.ini file..."
	echo -e "[cryptography]\nssfs_key_file_path = /usr/sap/$sid/SYS/global/hdb/security/ssfs\n" >> /usr/sap/$sid/SYS/global/hdb/custom/config/global.ini 
	echo

	echo "Re-encrypt the system PKI SSFS with new key..."
	export RSEC_SSFS_DATAPATH=/usr/sap/$sid/SYS/global/security/rsecssfs/data
	export RSEC_SSFS_KEYPATH=/usr/sap/$sid/SYS/global/security/rsecssfs/key
	rsecssfx changekey $(rsecssfx generatekey -getPlainValueToConsole)
	echo
}

#########################################################
# Set root key backup password
#########################################################
setRootKeyBackupPwd() {
	if [[ -z $(hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "ALTER SYSTEM SET ENCRYPTION ROOT KEYS BACKUP PASSWORD \"$backup_pwd\"" | grep "0 rows affected") ]]; then
		echo "Fail to set root key backup password for $db_name!"
		exit 1
	else
		echo "Root key backup password set for $db_name!"
	fi
}


#########################################################
# Generate root key
#########################################################
generateRootKey() {
	#Data Volumn Encryption
	if [[ -z $(hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "ALTER SYSTEM PERSISTENCE ENCRYPTION CREATE NEW ROOT KEY WITHOUT ACTIVATE" | grep "0 rows affected") ]]; then
		echo "Fail to generate root key for data volume of $db_name!"
		exit 1
	else
		echo "Root key generated for data volume of $db_name!"
	fi

	#Redo log Encryption
	if [[ -z $(hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "ALTER SYSTEM LOG ENCRYPTION CREATE NEW ROOT KEY WITHOUT ACTIVATE" | grep "0 rows affected") ]]; then
		echo "Fail to generate root key for redo log of $db_name!"
		exit 1
	else
		echo "Root key generated for redo log of $db_name!"
	fi

	#Internal Application Encryption
	if [[ -z $(hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "ALTER SYSTEM APPLICATION ENCRYPTION CREATE NEW ROOT KEY WITHOUT ACTIVATE" | grep "0 rows affected") ]]; then
		echo "Fail to generate root key for internal application of $db_name!"
		exit 1
	else
		echo "Root key generated for internal application of $db_name!"
	fi
}

#########################################################
# Backup root key
#########################################################
backupRootKey() {
	hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "SELECT ENCRYPTION_ROOT_KEYS_EXTRACT_KEYS ('PERSISTENCE, APPLICATION, LOG') FROM DUMMY" > $backup_dir/$db_name.rkb
	echo "Root key for $db_name is backed up to $backup_dir/$db_name.rkb!"
}

#########################################################
# Activate root key
#########################################################
activateRootKey() {
	#Data Volumn Encryption
	if [[ -z $(hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "ALTER SYSTEM PERSISTENCE ENCRYPTION ACTIVATE NEW ROOT KEY" | grep "0 rows affected") ]]; then
		echo "Fail to activate root key for data volume of $db_name!"
		exit 1
	else
		echo "Root key activated for data volume of $db_name!"
	fi

	#Redo log Encryption
	if [[ -z $(hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "ALTER SYSTEM LOG ENCRYPTION ACTIVATE NEW ROOT KEY" | grep "0 rows affected") ]]; then
		echo "Fail to activate root key for redo log of $db_name!"
		exit 1
	else
		echo "Root key activated for redo log of $db_name!"
	fi

	#Internal Application Encryption
	if [[ -z $(hdbsql -i ${instance_number} -d $db_name -u SYSTEM  -p ${system_pwd} "ALTER SYSTEM APPLICATION ENCRYPTION ACTIVATE NEW ROOT KEY" | grep "0 rows affected") ]]; then
		echo "Fail to activate root key for internal application of $db_name!"
		exit 1
	else
		echo "Root key activated for internal application of $db_name!"
	fi
}

#########################################################
# Prompt root key backup directory
#########################################################
promptRootKeyBackupDir() {
	while [ 1 ]; do
		read -p "Enter root key backup directory: " backup_dir
		if [ ! -d "$backup_dir" ] ; then
			echo
			echo "\"$backup_dir\" does not exist or not a directory."
			echo
		elif [ ! -w "$backup_dir" ] ; then
			echo
			echo "\"$backup_dir\" is not writable."
			echo
		else
			break
		fi
	done
}


#########################################################
# Print pre-install summary
#########################################################
printSummary() {
cat <<-EOF

##############################################################################
# Security keys change summary                                               #
##############################################################################
  HANA system ID            : ${sid}
  HANA instance number      : ${instance_number}
  system password           : ********
  root key backup password  : ********
  root key backup directory : ${backup_dir}

EOF

	while [ 1 ] ; do
		read -p "Proceed? (Y/N) : " proceed
		if [ "${proceed}" == "Y" -o "${proceed}" == "y" ]; then
			return
		elif [ "${proceed}" == "N" -o "${proceed}" == "n" ]; then
			exit 1
		fi
	done
}

#########################################################
# Main
#########################################################
instance_number="90"
sid="HXE"
system_pwd=""
backup_pwd=""
backup_dir=""
tenant_db_name=""

#
# Parse argument
#
if [ $# -gt 0 ]; then
	PARSED_OPTIONS=`getopt -n "$base_name" -a -o hd: -- "$@"`
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
		-h)
			usage
			exit 0
			break;;
		-d)
			tenant_db_name="$2"
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

getSID

promptInstanceNumber

promptPwd "system user" system_pwd

promptPwd "Root key backup" backup_pwd

promptRootKeyBackupDir 

printSummary

echo

echo "#############################"
echo "# Changing SSFS Master keys #"
echo "#############################"
changeSSFSKeys

echo "#########################################"
echo "# Change root key for SystemDB database #"
echo "#########################################"
db_name="SYSTEMDB"
setRootKeyBackupPwd
generateRootKey
backupRootKey
activateRootKey

if [ -z "$tenant_db_name" ]; then
	db_name="$sid"
else
	db_name="$tenant_db_name"
fi
echo "###########################################"
echo "# Change root key for tenant database $db_name #"
echo "###########################################"
setRootKeyBackupPwd
generateRootKey
backupRootKey
activateRootKey

#!/bin/bash

############################################################################################
# This utility is used to create a tenant database and register the database for telemetry
############################################################################################

############################################################################################
# Print usage
############################################################################################
usage() {
cat <<-EOF

This utility creates a tenant database and registers the database for telemetry.

Usage:
   $PROG_NAME [options]

   -p   <system_user_password>      System user password
   -xu  <xsa_admin_user_name>       XSA administrator user name
   -xp  <xsa_admin_user_password>   XSA administrator user password
   -tu  <telemetry_user_name>       Telemetry technical user name
   -tp  <telemetry_user_password>   Telemetry technical user password

   -i   <instance number>           HANA database instance number
   -d   <new tenant db name>        New tenant database name
   -s   <space>                     Space. Default is "SAP".

   -up  <"true"|"false">            Use proxy server
   -ph  <proxy_host>                Proxy host
   -pp  <proxy_port>                Proxy port
   -nph <no_proxy_hosts>            Comma separated list of hosts that do not
                                    need proxy.

   -h                               Print this help

EOF
}

############################################################################################
# Get SID from current user login <sid>adm
############################################################################################
getSID() {
	me=`whoami`
	if echo $me | grep 'adm$' >& /dev/null; then
		sid=`echo $me | cut -c1-3 | tr '[:lower:]' '[:upper:]'`
		if [ ! -d /hana/shared/${sid} ]; then
			echo "You login as \"$me\"; but SID \"${sid}\" (/hana/shared/${sid}) does not exist."
			exit 1
		fi
	else
		echo "You need to run this from HANA administrator user \"<sid>adm\"."
		exit 1
	fi
}

############################################################################################
# Prompt user password
############################################################################################
# arg 1: Description
# arg 2: variable name to store user name value
# arg 3  Default user name if arg 2 is empty
# arg 4: variable name to store password value
#
promptUserPwd() {
	local default_user=`echo ${!2}`
	local usr=""
	local pwd=""
	if [ -z "$default_user" ]; then
		default_user="$3"
		read -p "Enter ${1} user name [${default_user}]: " usr
		if [ -n "$usr" ]; then
			default_user=$usr
		fi
		eval $2=\$default_user
	fi

	if [ -z "`echo ${!4}`" ]; then
		read -s -p "Enter $default_user user password: " pwd
		eval $4=\$pwd
	fi

	echo
}

############################################################################################
# Prompt instance number
############################################################################################
promptInstanceNumber() {
	if [ -n "$instance_number" ] && [ -d /hana/shared/${sid}/HDB${instance_number} ] ; then
		return
	fi

	instance_number="90"
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

############################################################################################
# Prompt tenant database name
############################################################################################
promptTenantDBName() {
	local dbname=""
	while [ 1 ]; do
		read -p "Enter tenant database name: " dbname
		if [ -n "$dbname" ]; then
			eval $1=\$dbname
			return
		fi
	done
}

# Prompt proxy host and port
############################################################################################
promptProxyInfo() {
	getSystemHTTPProxy

	if [ -z "$use_proxy" ]; then
		while [ 1 ] ; do
			read -p "Do you need to use proxy server to access the internet? (Y/N): " tmp
			if [ "$tmp" == "Y" -o "$tmp" == "y" ]; then
				use_proxy=1
				break
			elif [ "$tmp" == "N" -o "$tmp" == "n" ]; then
				use_proxy=0
				break
			else
				echo "Invalid input.  Enter \"Y\" or \"N\"."
			fi
		done
	fi

	if [ $use_proxy -ne 1 ]; then
		return
	fi

	# Proxy host
	if [ -z "$proxy_host" ]; then
		while [ 1 ]; do
			read -p "Enter proxy host name [$system_proxy_host]: " tmp
			if [ -z "$tmp" ]; then
				if [ -n "$system_proxy_host" ]; then
					tmp="$system_proxy_host"
				else
					continue
				fi
			fi
			if ! $(isValidHostName "$tmp"); then
				echo
				echo "\"$tmp\" is not a valid host name or IP address."
				echo
			else
				proxy_host="$tmp"
				break
			fi
		done
	fi

	# Proxy port
	if [ -z "$proxy_port" ]; then
		while [ 1 ]; do
			read -p "Enter proxy port number [$system_proxy_port]: " tmp
			if [ -z "$tmp" ]; then
				if [ -n "$system_proxy_port" ]; then
					tmp="$system_proxy_port"
				else
					continue
				fi
			fi
			if ! $(isValidPort "$tmp"); then
				echo
				echo "\"$tmp\" is not a valid port number."
				echo "Enter number between 1 and 65535."
				echo
			else
				proxy_port="$tmp"
				break
			fi
		done
	fi

	# No proxy hosts
	if [ -z "$no_proxy_host" ]; then
		read -p "Enter comma separated domains that do not need proxy [$system_no_proxy_host]: " tmp
		if [ -z "$tmp" ]; then
			no_proxy_host="$system_no_proxy_host"
		else
			no_proxy_host="$tmp"
		fi
	fi
}


############################################################################################
# Get the system proxy host and port
############################################################################################
getSystemHTTPProxy() {
	local url="$https_proxy"
	local is_https_port=1

	if [ -z "$url" ]; then
		url="$http_proxy"
		is_https_port=0
	fi
	if [ -z "$url" ] && [ -f /etc/sysconfig/proxy ]; then
		url=`grep ^HTTPS_PROXY /etc/sysconfig/proxy | cut -d'=' -f2`
		is_https_port=1
	fi
	if [ -z "$url" ] && [ -f /etc/sysconfig/proxy ]; then
		url=`grep ^HTTP_PROXY /etc/sysconfig/proxy | cut -d'=' -f2`
		is_https_port=0
	fi

	url="${url%\"}"
	url="${url#\"}"
	url="${url%\'}"
        url="${url#\'}"

	if [ -z "$url" ]; then
		return
	fi

	# Get proxy host
	system_proxy_host=$url
	if echo $url | grep -i '^http' >& /dev/null; then
		system_proxy_host=`echo $url | cut -d '/' -f3 | cut -d':' -f1`
	else
		system_proxy_host=`echo $url | cut -d '/' -f1 | cut -d':' -f1`
	fi

	# Get proxy port
	if echo $url | grep -i '^http' >& /dev/null; then
		if echo $url | cut -d '/' -f3 | grep ':' >& /dev/null; then
			system_proxy_port=`echo $url | cut -d '/' -f3 | cut -d':' -f2`
		elif [ $is_https_port -eq 1 ]; then
			system_proxy_port="443"
		else
			system_proxy_port="80"
		fi
	else
		if echo $url | cut -d '/' -f1 | grep ':' >& /dev/null; then
			system_proxy_port=`echo $url | cut -d '/' -f1 | cut -d':' -f2`
		elif [ $is_https_port -eq 1 ]; then
			system_proxy_port="443"
		else
			system_proxy_port="80"
		fi
        fi

	# Get no proxy hosts
	system_no_proxy_host="$no_proxy"
	if [ -z "$system_no_proxy_host" ] && [ -f /etc/sysconfig/proxy ]; then
		system_no_proxy_host=`grep ^NO_PROXY /etc/sysconfig/proxy | cut -d'=' -f2`
		system_no_proxy_host="${system_no_proxy_host%\"}"
		system_no_proxy_host="${system_no_proxy_host#\"}"
		system_no_proxy_host="${system_no_proxy_host%\'}"
		system_no_proxy_host="${system_no_proxy_host#\'}"
	fi
	if [ -z "$system_no_proxy_host" ] && [ -f /etc/sysconfig/proxy ]; then
		system_no_proxy_host=`grep ^no_proxy /etc/sysconfig/proxy | cut -d'=' -f2`
		system_no_proxy_host="${system_no_proxy_host%\"}"
		system_no_proxy_host="${system_no_proxy_host#\"}"
		system_no_proxy_host="${system_no_proxy_host%\'}"
		system_no_proxy_host="${system_no_proxy_host#\'}"
	fi
}

isValidHostName() {
	local hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
	echo "$1" | egrep $hostname_regex >& /dev/null
}

isValidPort() {
	if [[ $1 =~ ^[0-9]?+$ ]]; then
		if [ $1 -ge 1 ] && [ $1 -le 65535 ]; then
			return 0
		else
			return 1
		fi
	else
		return 1
	fi
}

############################################################################################
# Create tenant database
############################################################################################
createTenantDB(){
	echo "Create tenant database $tenant_db..."
	if [[ -z $(hdbsql -i ${instance_number} -d SystemDB -u $system -p "$system_pwd" "create database $tenant_db system user password \"$system_pwd\"" | grep "0 rows affected") ]]; then
		echo "  ERROR: Fail to create tenant database $tenant_db"
		exit 1
	fi
}

############################################################################################
# Create technical user in the tenant database, grant permissions and update telemetry server URL
############################################################################################
createTechUserAndUpdateUrl() {
	echo "Create telemetry technical user $tech_user on $tenant_db database..."
	hdbsql -i $instance_number -d $tenant_db -u $system -p "$system_pwd" "CREATE USER $tech_user PASSWORD \"$tech_user_pwd\" NO FORCE_FIRST_PASSWORD_CHANGE" 
	hdbsql -i $instance_number -d $tenant_db -u $system -p "$system_pwd" "ALTER USER $tech_user DISABLE PASSWORD LIFETIME" 
	# wait a little bit before granting permission
	sleep 60s
	hdbsql -i $instance_number -d $tenant_db -u $system -p "$system_pwd" "grant SELECT, INSERT, UPDATE, DELETE, EXECUTE on schema _SYS_TELEMETRY to $tech_user" 
	hdbsql -i $instance_number -d $tenant_db -u $system -p "$system_pwd" "grant SELECT on schema _SYS_STATISTICS to $tech_user" 
	hdbsql -i $instance_number -d $tenant_db -u $system -p "$system_pwd" "grant CATALOG READ to $tech_user" 

	echo "Change telemetry URL for $tenant_db database..."
	${PROG_DIR}/hxe_telemetry.sh -d $tenant_db -i $instance_number -u $tech_user -c "${TEL_URL}" <<-EOF
$tech_user_pwd
EOF
}

############################################################################################
# Configure proxy 
############################################################################################
configureProxy(){
	echo "Configure proxy..."
	${PROG_DIR}/register_cockpit.sh -action config_proxy -proxy_action enable_http <<-EOF
${xsa_admin}
${xsa_admin_pwd}
${instance_number}
${proxy_host}
${proxy_port}
${no_proxy_host}
EOF
}

############################################################################################
# Register the tenant database
############################################################################################
registerResource(){
	echo "Register tenant database $tenant_db..."
	${PROG_DIR}/register_cockpit.sh -action register -d $tenant_db -i $instance_number <<-EOF
${system}
${system_pwd}
$xsa_admin
$xsa_admin_pwd
$tech_user
$tech_user_pwd
EOF
}

############################################################################################
# Main
############################################################################################
# Default values
DEFAULT_SYSTEM_ADMIN="SYSTEM"
DEFAULT_XSA_ADMIN="XSA_ADMIN"
DEFAULT_TECH_USER="TEL_ADMIN"
TEL_URL="https://telemetry.cloud.sap"

PROG_DIR="$(cd "$(dirname ${0})"; pwd)"
PROG_NAME=`basename $0`

# Inputs
sid="HXE"
instance_number=""
system="$DEFAULT_SYSTEM_ADMIN"
system_pwd=""
xsa_admin=""
xsa_admin_pwd=""
tech_user=""
tech_user_pwd=""
tenant_db=""
space="SAP"
use_proxy=""
system_proxy_host=""
system_proxy_port=""
system_no_proxy_host=""
proxy_host=""
proxy_port=""
no_proxy_host=""

#
# Parse argument
#
if [ $# -gt 0 ]; then
	PARSED_OPTIONS=`getopt -n "$PROG_NAME" -a -o p:i:d:s:h --long xu:,xp:,tu:,tp:,up:,ph:,pp:,nph: -- "$@"`
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
		-p)
			system_pwd="$2"
			shift 2;;
		-i)
			instance_number="$2"
			shift 2;;
		-d)
			tenant_db="$2"
			shift 2;;
		-s)
			space="$2"
			shift 2;;
		-h)
			usage
			exit 0
			break;;
		-xu|--xu)
			xsa_admin="$2"
			shift 2;;
		-xp|--xp)
			xsa_admin_pwd="$2"
			shift 2;;
                -tu|--tu)
			tech_user="$2"
			shift 2;;
		-tp|--tp)
			tech_user_pwd="$2"
			shift 2;;
		-up|--up)
			use_proxy=`echo "${2}" | tr '[:upper:]' '[:lower:]'`
			if [ "${use_proxy}" != "true" -a "${use_proxy}" != "false" -a "${use_proxy}" != "1" -a "${use_proxy}" != "0" ]; then
				echo
				echo "Invalid '-up' option value.  Valid values are: true, false."
				exit 1
			fi
			if [ "${use_proxy}" == "true" -o "${use_proxy}" == "1" ]; then
				use_proxy=1
			else
				use_proxy=0
			fi
			shift 2;;
		-ph|--ph)
			proxy_host="$2"
			if ! $(isValidHostName "$proxy_host"); then
				echo
				echo "\"$proxy_host\" is not a valid host name or IP address."
				exit 1
			fi
			shift 2;;
		-pp|--pp)
			proxy_port="$2"
			if ! $(isValidPort "$proxy_port"); then
				echo
				echo "\"$proxy_port\" is not a valid port number."
				echo "Enter number between 1 and 65535."
				exit 1
			fi
			shift 2;;
		-nph|--nph)
			no_proxy_host="$2"
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

# Prompt system password if not provided
if [ -z "$system" -o -z "$system_pwd" ]; then
	promptUserPwd "system" system $DEFAULT_SYSTEM_ADMIN system_pwd
fi

# Prompt XSA administrator user/password if not provided
if [ -z "$xsa_admin" -o -z "$xsa_admin_pwd" ]; then
	promptUserPwd "XSA administrator" xsa_admin $DEFAULT_XSA_ADMIN xsa_admin_pwd
fi

# Prompt telemetry technical user/password if not provided
if [ -z "$tech_user" -o -z "$tech_user_pwd" ]; then
	promptUserPwd "telemetry technical" tech_user $DEFAULT_TECH_USER tech_user_pwd
fi

promptInstanceNumber

# Prompt tenant database if not provided
if [ -z "$tenant_db" ]; then
	promptTenantDBName tenant_db
fi

promptProxyInfo

createTenantDB
createTechUserAndUpdateUrl
if [ $use_proxy -eq 1 ]; then
	configureProxy
fi
registerResource 
echo
echo "Successfully created tenant database $tenant_db!"
echo


#!/bin/bash

echo ""
read -p "Enter fully qualified host name: " fqdn

cmd="cd HANA_EXPRESS_20/DATA_UNITS/HDB_LCM_LINUX_X86_64/configurations"
echo $cmd
#eval $cmd

cmd="cp auto_install.cfg auto_install_cfg.bak"
echo $cmd
#eval $cmd

cmd='sed -i -e "s/xs_routing_mode=ports/xs_routing_mode=hostnames/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/xs_domain_name=USE_DEFAULT/xs_domain_name='$fqdn'/g" auto_install.cfg'
echo $cmd
#eval $cmd

echo ""
read -p "Enter organization name: " orgname

cmd='sed -i -e "s/org_name=HANAExpress/org_name='$orgname'/g" auto_install.cfg'
echo $cmd
#eval $cmd

echo ""
read -p "Enter development space name: " devspace

cmd='sed -i -e "s/prod_space_name=development/prod_space_name='$devspace'/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd="cd ../../../.."
echo $cmd
#eval $cmd

echo "Reset with..."
echo "cp HANA_EXPRESS_20/DATA_UNITS/HDB_LCM_LINUX_X86_64/configurations/auto_install_cfg.bak HANA_EXPRESS_20/DATA_UNITS/HDB_LCM_LINUX_X86_64/configurations/auto_install.cfg"

echo ""
echo "Now run the setup_hxe.sh script"
echo ""

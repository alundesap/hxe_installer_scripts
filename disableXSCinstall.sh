#!/bin/bash
#
# Enable eval with..
# %s/#eval \$cmd/eval \$cmd/g
#
# Disable eval with..
# %s/eval \$cmd/#eval \$cmd/g

echo ""
read -p "Enter fully qualified host name: " fqdn

echo ""
read -p "Enter organization name: " orgname

cmd="cd HANA_EXPRESS_20/DATA_UNITS/HDB_LCM_LINUX_X86_64/configurations"
echo $cmd
#eval $cmd

#cmd="cp auto_install.cfg auto_install_cfg.bak"
#echo $cmd
##eval $cmd

#cmd="cp auto_update.cfg auto_update_cfg.bak"
#echo $cmd
##eval $cmd

cmd='sed -i -e "s/xs_routing_mode=ports/xs_routing_mode=hostnames/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/xs_domain_name=USE_DEFAULT/xs_domain_name='$fqdn'/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/org_name=HANAExpress/org_name='$orgname'/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/org_name=HANAExpress/org_name='$orgname'/g" auto_update.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/hdbinst_server_xs_engine=on/hdbinst_server_xs_engine=off/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/hdbinst_server_import_content=on/hdbinst_server_import_content=off/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/instances = 1/instances = 0/g" custom/daemon.ini'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/embedded = true/embedded = false/g" custom/nameserver.ini'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/embedded = true/embedded = false/g" custom/xsengine.ini'
echo $cmd
#eval $cmd

cmd="cd ../../../.."
echo $cmd
#eval $cmd

cmd="cd HANA_EXPRESS_20/DATA_UNITS/HDB_SERVER_LINUX_X86_64/configurations"
echo $cmd
#eval $cmd

#cmd="cp auto_install.cfg auto_install_cfg.bak"
#echo $cmd
##eval $cmd

#cmd="cp auto_update.cfg auto_update_cfg.bak"
#echo $cmd
##eval $cmd

cmd='sed -i -e "s/xs_routing_mode=ports/xs_routing_mode=hostnames/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/xs_routing_mode=ports/xs_routing_mode=hostnames/g" auto_update.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/xs_domain_name=USE_DEFAULT/xs_domain_name='$fqdn'/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/xs_domain_name=USE_DEFAULT/xs_domain_name='$fqdn'/g" auto_update.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/org_name=HANAExpress/org_name='$orgname'/g" auto_install.cfg'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/org_name=HANAExpress/org_name='$orgname'/g" auto_update.cfg'
echo $cmd
#eval $cmd

cmd="cd ../../.."
echo $cmd
#eval $cmd

#cmd="cp hxe_optimize.sh hxe_optimize_sh.bak"
#echo $cmd
##eval $cmd

#cmd="cp hxe_upgrade.sh hxe_upgrade_sh.bak"
#echo $cmd
##eval $cmd

cmd='sed -i -e "s/ORG_NAME=\"HANAExpress\"/ORG_NAME=\"'$orgname'\"/g" hxe_optimize.sh'
echo $cmd
#eval $cmd

cmd='sed -i -e "s/ORG_NAME=\"HANAExpress\"/ORG_NAME=\"'$orgname'\"/g" hxe_upgrade.sh'
echo $cmd
#eval $cmd

cmd="cd .."
echo $cmd
#eval $cmd

cmd='sed -i -e "s/ORG_NAME=\"HANAExpress\"/ORG_NAME=\"'$orgname'\"/g" setup_hxe.sh'
echo $cmd
#eval $cmd

echo ""
echo 'Verify that your /etc/hosts file contains '$fqdn' on the loopback(127.0.0.1) line and no others.'
echo "Example.."
echo '127.0.0.1       localhost '$fqdn

echo ""
echo 'Also verify that external wildcard DNS resolution is correctly reports various hostname combinations like abc.'$fqdn' or xyz.'$fqdn' as the EXTERNAL IP address of your server.'
echo ""
echo ""
echo 'Now run the setup_hxe.sh script.  Supply '$fqdn' when prompted for the server hostname.'
echo ""
echo "./setup_hxe.sh"
echo ""

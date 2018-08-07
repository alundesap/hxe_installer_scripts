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
read -p "Enter SYSTEMDB's SYSTEM user's password: " syspw

cmd="sudo -u hxeadm /usr/sap/HXE/HDB00/exe/hdbsql -u SYSTEM -p $syspw -i 00 -d SYSTEMDB \"alter system alter configuration('xscontroller.ini','SYSTEM') SET ('communication','router_port') = '443' with reconfigure\""
echo $cmd
#eval $cmd

cmd="sudo -u hxeadm /usr/sap/HXE/HDB00/exe/hdbsql -u SYSTEM -p $syspw -i 00 -d SYSTEMDB \"alter system alter configuration('xscontroller.ini','SYSTEM') SET ('communication','listen_port') = '443' with reconfigure\""
echo $cmd
#eval $cmd

cmd="sudo -u hxeadm /usr/sap/HXE/HDB00/exe/hdbsql -u SYSTEM -p $syspw -i 00 -d SYSTEMDB \"alter system alter configuration('xscontroller.ini','SYSTEM') SET ('communication','api_url') = 'https://api.$fqdn:443' with reconfigure\""
echo $cmd
#eval $cmd

cmd="sudo -u hxeadm /usr/sap/HXE/HDB00/exe/hdbsql -u SYSTEM -p $syspw -i 00 -d SYSTEMDB \"SELECT LAYER_NAME,KEY,VALUE FROM M_INIFILE_CONTENTS WHERE FILE_NAME='xscontroller.ini' AND LAYER_NAME='SYSTEM'\""
echo ""
echo $cmd
echo ""
#eval $cmd

echo "Verify things before continuing."
echo ""
read -p "Press enter to continue.  Ctrl-C to break: " rebnow
echo ""
echo ""

cmd="pushd /hana/shared/HXE/xs/router/webdispatcher"
echo $cmd
#eval $cmd

cmd="cp icmbnd.new icmbnd"
echo $cmd
#eval $cmd

cmd="chown root:sapsys icmbnd"
echo $cmd
#eval $cmd

cmd="chmod 4750 icmbnd"
echo $cmd
#eval $cmd

cmd="ls -al icmbnd"
echo $cmd
#eval $cmd


cmd="popd"
echo $cmd
#eval $cmd

echo "cd /hana/shared/HXE"
echo "find . -name xscontroller.ini -print"
echo "cd /hana/shared/HXE/exe/linuxx86_64/HDB_2.00.031.00.1528768600_0d29bcd47c52b9ec46d38c93a44d168fdac79164/config"
echo "vi xscontroller.ini"
echo "XSA restage-at-startup"
echo "XSA set-certificate -c /tmp/parvus.lcfx.net.pem -k /tmp/parvus.lcfx.net.key"
echo ""

read -p "System will reboot after pressing enter.  Ctrl-C to break: " rebnow

echo ""

cmd="shutdown -r 2"
echo $cmd
#eval $cmd


echo ""
echo "Rebooting..."
sleep 1
echo ""

#!/bin/bash

if grep -q ${netappip} /etc/fstab; then
    # If have already done in the past
    exit 0
fi

sudo yum install -y nfs-utils
mkdir /u02
echo "${netappip}:/${netappvol}       /u02            nfs   rw,bg,hard,vers=3,proto=tcp,timeo=600,rsize=262144,wsize=262144,nointr     0 0" | tee -a /etc/fstab
mount /u02
chmod 777 /u02
firewall-cmd --zone=public --add-port=1521/tcp --permanent
firewall-cmd --zone=public --add-port=5502/tcp --permanent
firewall-cmd --reload

if [ ${node} -eq 0 ]; then
    sudo -i -u oracle mkdir /u02/oradata
    sudo -i -u oracle lsnrctl start
    sudo -i -u oracle dbca -silent \
        -createDatabase \
        -templateName General_Purpose.dbc \
        -gdbname orcl \
        -sid orcl \
        -responseFile NO_VALUE \
        -characterSet AL32UTF8 \
        -sysPassword OraPasswd1 \
        -systemPassword OraPasswd1 \
        -createAsContainerDatabase false \
        -databaseType MULTIPURPOSE \
        -automaticMemoryManagement false \
        -storageType FS \
        -datafileDestination "/u02/oradata/" \
        -ignorePreReqs
    sudo -i -u oracle mv /u01/app/oracle/product/19.0.0/dbhome_1/dbs/spfileorcl.ora /u02/oradata
else
    sudo -i -u oracle mkdir -p /u01/app/oracle/admin/orcl/adump /u01/app/oracle/admin/orcl/dpdump /u01/app/oracle/admin/orcl/pfile /u01/app/oracle/admin/orcl/xdb_wallet
fi
echo "SPFILE='/u02/oradata/spfileorcl.ora'" | sudo -i -u oracle tee /u01/app/oracle/product/19.0.0/dbhome_1/dbs/initorcl.ora
echo "orcl = (DESCRIPTION = (ADDRESS_LIST = (ADDRESS = (PROTOCOL = TCP)(HOST = ${myip})(PORT = 1521))) (CONNECT_DATA = (SID = orcl)))" | sudo -i -u oracle tee /u01/app/oracle/product/19.0.0/dbhome_1/network/admin/tnsnames.ora

sudo yum install -y pcs pacemaker fence-agents-azure-arm nmap-ncat
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --add-service=high-availability

(
echo ${ospassword}
echo ${ospassword}
) | passwd hacluster

systemctl start pcsd.service
systemctl enable pcsd.service

if [ ${node} -eq 0 ]; then
    (
    echo hacluster
    echo ${ospassword}
    ) | pcs cluster auth ${vmname0} ${vmname1}

    pcs cluster setup --start --name my_cluster ${vmname0} ${vmname1}
    pcs cluster enable --all
    pcs quorum expected-votes 2

    pcs property set concurrent-fencing=false
    pcs property set stonith-enabled=false
    pcs property set no-quorum-policy=ignore

    pcs resource defaults resource-stickiness=INFINITY migration-threshold=10
    pcs resource create OraLsnr ocf:heartbeat:oralsnr sid="orcl" home="/u01/app/oracle/product/19.0.0/dbhome_1" user="oracle" op start interval="0s" timeout="120s" op stop interval="0s" timeout="120s" op monitor interval="30s" timeout="60s" on-fail="restart"
    pcs resource create OraSrv ocf:heartbeat:oracle sid=orcl home="/u01/app/oracle/product/19.0.0/dbhome_1" user=oracle op start interval="0s" timeout="120" on-fail="restart" op stop interval="0s" timeout="120" on-fail="block" op monitor interval="30s" timeout="60s" on-fail="restart"
    pcs constraint colocation add OraSrv with OraLsnr score=INFINITY
    pcs constraint order set OraLsnr OraSrv
fi
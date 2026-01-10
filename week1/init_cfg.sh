#!/usr/bin/env bash

echo ">>>> Initial Config Start <<<<"

echo "[TASK 1] Setting Profile & Bashrc"
echo "sudo su -" >> /home/vagrant/.bashrc
echo 'alias vi=vim' >> /etc/profile
ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime # Change Timezone

echo "[TASK 2] Disable Firewall"
systemctl stop firewalld && systemctl disable firewalld >/dev/null 2>&1

echo "[TASK 3] Disable and turn off SWAP"
swapoff -a && sed -i '/swap/s/^/#/' /etc/fstab

echo "[TASK 4] Install Packages"
YQ_VERSION=v4.2.0
PLATFORM=linux_arm64  #$(uname -m), 수정하기 나중에 
dnf update -qq >/dev/null 2>&1
dnf install epel-release -y -qq >/dev/null 2>&1
dnf install tree git jq unzip vim sshpass -y -qq >/dev/null 2>&1
wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${PLATFORM} -O /usr/local/bin/yq &&\
    chmod +x /usr/local/bin/yq

echo "[TASK 5] Setting Root Password"
echo "root:qwe123" | chpasswd

echo "[TASK 6] Setting Sshd Config"
cat << EOF >> /etc/ssh/sshd_config
PasswordAuthentication yes
PermitRootLogin yes
EOF
systemctl restart sshd  >/dev/null 2>&1

echo "[TASK 7] Setting Local DNS Using Hosts file"
sed -i '/^127\.0\.\(1\|2\)\.1/d' /etc/hosts
cat << EOF >> /etc/hosts
192.168.10.10  jumpbox
192.168.10.100 server.kubernetes.local server 
192.168.10.101 node-0.kubernetes.local node-0
192.168.10.102 node-1.kubernetes.local node-1
EOF


echo ">>>> Initial Config End <<<<"
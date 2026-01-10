### k8s1.35 The Hard Way (rocky linux)
rocky 9.7, kernal 5.14에서 k8s 1.35를 하나씩 구축하는 과정이다. 파드 생성까지 서비스 생성(노드 포트)까지 테스트는 완료했으나, 커널 파라미터 설정, [커널에 따른 기능 지원 버전](https://kubernetes.io/docs/reference/node/kernel-version-requirements/)등으로 인해 k8s v1.35에서 제공하는 모든 기능이 동작하지 않을 것으로 보인다. 


### vagrant 명령어 정리 
```sh
# vm 생성
vagrant up
vagrant box list
vagrant status
# vm 리소스 정리 
vagrant destroy -f && rm -rf .vagrant
```

### ch2 Set Up The Jumpbox
```sh
vagrant ssh jumpbox

git clone --depth 1 https://github.com/kelseyhightower/kubernetes-the-hard-way.git
cd kubernetes-the-hard-way
tree
pwd 

ARCH=$(rpm --eval '%{_arch}')
if [ "$ARCH" = "aarch64" ]; then
  BIN_ARCH="arm64"
else
  BIN_ARCH="amd64"
fi
echo "$BIN_ARCH"

# os에 맞는 다운로드 파일 읽기
cat downloads-${BIN_ARCH}.txt 

# k8s 컴포넌트 버전 치환 1.32 -> 1.35
sed -i 's/v1\.32\.3/v1.35\.0/g' downloads-${BIN_ARCH}.txt 
sed -i 's/v1\.32\.0/v1.35\.0/g' downloads-${BIN_ARCH}.txt 

# k8s v1.35에 일치하거나 최신 버전 사용
vi downloads-${BIN_ARCH}.txt 
https://github.com/containerd/containerd/releases/download/v2.2.0/containerd-2.2.0-linux-arm64.tar.gz
https://github.com/containernetworking/plugins/releases/download/v1.9.0/cni-plugins-linux-arm64-v1.9.0.tgz
https://github.com/opencontainers/runc/releases/download/v1.3.4/runc.arm64
https://github.com/etcd-io/etcd/releases/download/v3.6.7/etcd-v3.6.7-linux-arm64.tar.gz

wget -q --show-progress \
  --https-only \
  --timestamping \
  -P downloads \
  -i downloads-${BIN_ARCH}.txt

ls -oh downloads
total 456M
-rw-r--r--. 1 root 49M Dec  9 19:49 cni-plugins-linux-arm64-v1.9.0.tgz
-rw-r--r--. 1 root 31M Nov  6 10:34 containerd-2.2.0-linux-arm64.tar.gz
-rw-r--r--. 1 root 17M Dec 10 17:44 crictl-v1.35.0-linux-arm64.tar.gz
-rw-r--r--. 1 root 22M Dec 18 04:47 etcd-v3.6.7-linux-arm64.tar.gz
-rw-r--r--. 1 root 77M Dec 18 03:03 kube-apiserver
-rw-r--r--. 1 root 64M Dec 18 03:03 kube-controller-manager
-rw-r--r--. 1 root 53M Dec 18 03:03 kubectl
-rw-r--r--. 1 root 52M Dec 18 03:03 kubelet
-rw-r--r--. 1 root 39M Dec 18 03:03 kube-proxy
-rw-r--r--. 1 root 43M Dec 18 03:03 kube-scheduler
-rw-r--r--. 1 root 12M Nov 28 08:31 runc.arm64

mkdir -p downloads/{client,cni-plugins,controller,worker}
tree -d downloads
downloads
├── client
├── cni-plugins
├── controller
└── worker

tar -xvf downloads/crictl-v1.35.0-linux-${BIN_ARCH}.tar.gz \
  -C downloads/worker/ && tree -ug downloads

tar -xvf downloads/containerd-2.2.0-linux-${BIN_ARCH}.tar.gz \
  --strip-components 1 \
  -C downloads/worker/ && tree -ug downloads

tar -xvf downloads/cni-plugins-linux-${BIN_ARCH}-v1.9.0.tgz \
  -C downloads/cni-plugins/ && tree -ug downloads

tar -xvf downloads/etcd-v3.6.7-linux-${BIN_ARCH}.tar.gz \
  -C downloads/ \
  --strip-components 1 \
  etcd-v3.6.7-linux-${BIN_ARCH}/etcdctl \
  etcd-v3.6.7-linux-${BIN_ARCH}/etcd && tree -ug downloads

tree downloads/worker/
tree downloads/cni-plugins
ls -l downloads/{etcd,etcdctl}

mv downloads/{etcdctl,kubectl} downloads/client/
mv downloads/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler} downloads/controller/
mv downloads/{kubelet,kube-proxy} downloads/worker/
mv downloads/runc.${BIN_ARCH} downloads/worker/runc

tree downloads/client/
tree downloads/controller/
tree downloads/worker/

ls -l downloads/*gz
rm -rf downloads/*gz

chmod +x downloads/{client,cni-plugins,controller,worker}/*
ls -l downloads/{client,cni-plugins,controller,worker}/*

chown root:root downloads/client/etcdctl
chown root:root downloads/controller/etcd
chown root:root downloads/worker/crictl

tree -ug downloads
ls -l downloads/client/kubectl
cp downloads/client/kubectl /usr/local/bin/

kubectl version --client
Client Version: v1.35.0
Kustomize Version: v5.7.1
```

### ch3 Provisioning Compute Resources
```sh
cat <<EOF > machines.txt
192.168.10.100 server.kubernetes.local server
192.168.10.101 node-0.kubernetes.local node-0 10.200.0.0/24
192.168.10.102 node-1.kubernetes.local node-1 10.200.1.0/24
EOF
cat machines.txt

while read IP FQDN HOST SUBNET; do
  echo "${IP} ${FQDN} ${HOST} ${SUBNET}"
done < machines.txt

grep "^[^#]" /etc/ssh/sshd_config
PasswordAuthentication yes
PermitRootLogin yes

ls -al /root/.ssh 

ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
ls -l /root/.ssh
-rw-------. 1 root root 2602 Jan 10 19:14 id_rsa
-rw-r--r--. 1 root root  566 Jan 10 19:14 id_rsa.pub

while read IP FQDN HOST SUBNET; do
  sshpass -p 'qwe123' ssh-copy-id -o StrictHostKeyChecking=no root@${IP}
done < machines.txt

while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} cat /root/.ssh/authorized_keys
done < machines.txt

while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} hostname
done < machines.txt

while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} cat /etc/hosts
done < machines.txt

while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} hostname --fqdn
done < machines.txt

while read IP FQDN HOST SUBNET; do
  sshpass -p 'qwe123' ssh -n -o StrictHostKeyChecking=no root@${HOST} hostname
done < machines.txt

while read IP FQDN HOST SUBNET; do
  sshpass -p 'qwe123' ssh -n root@${HOST} uname -o -m -n
done < machines.txt
```


### ch4 Provisioning a CA and Generating TLS Certificates
```sh
cat ca.conf

# ca.key -> ca.key + ca.conf -> ca.crt
# root CA 개인키 생성 
openssl genrsa -out ca.key 4096
ls -l ca.key

openssl rsa -in ca.key -text -noout # 개인키 구조 확인

openssl req -x509 -new -sha512 -noenc \
    -key ca.key -days 3653 \
    -config ca.conf \
    -out ca.crt

###### 해당 항목을 작업하는 이유에 대해서 잘 모르겟음 
openssl genrsa -out admin.key 4096
openssl req -new -key admin.key -sha256 \
  -config ca.conf -section admin \
  -out admin.csr
openssl req -in admin.csr -text -noout # CSR 전체 내용 확인
openssl x509 -req -days 3653 -in admin.csr \
  -copy_extensions copyall \
  -sha256 -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out admin.crt

# 오타 수정 
cat ca.conf | grep system:kube-scheduler
CN = system:kube-scheduler
O  = system:system:kube-scheduler

sed -i 's/system:system:kube-scheduler/system:kube-scheduler/' ca.conf
cat ca.conf | grep system:kube-scheduler
CN = system:kube-scheduler
O  = system:kube-scheduler

# 변수 
certs=(
  "admin" "node-0" "node-1"
  "kube-proxy" "kube-scheduler"
  "kube-controller-manager"
  "kube-api-server"
  "service-accounts"
)
echo ${certs[*]}

for i in ${certs[*]}; do
  openssl genrsa -out "${i}.key" 4096

  openssl req -new -key "${i}.key" -sha256 \
    -config "ca.conf" -section ${i} \
    -out "${i}.csr"

  openssl x509 -req -days 3653 -in "${i}.csr" \
    -copy_extensions copyall \
    -sha256 -CA "ca.crt" \
    -CAkey "ca.key" \
    -CAcreateserial \
    -out "${i}.crt"
done

ls -1 *.crt *.key *.csr | wc -l 
26 

openssl x509 -in node-0.crt -text -noout
openssl x509 -in node-1.crt -text -noout
openssl x509 -in kube-proxy.crt -text -noout
openssl x509 -in kube-scheduler.crt -text -noout
openssl x509 -in kube-controller-manager.crt -text -noout
openssl x509 -in kube-api-server.crt -text -noout
openssl x509 -in service-accounts.crt -text -noout

# 모든 k8s 노드 인증서 배포 
for host in node-0 node-1; do
  ssh root@$host mkdir /var/lib/kubelet/

  scp ca.crt root@$host:/var/lib/kubelet/

  scp $host.crt \
    root@$host:/var/lib/kubelet/kubelet.crt

  scp $host.key \
    root@$host:/var/lib/kubelet/kubelet.key
done

ssh node-0 ls -l /var/lib/kubelet # node-1

scp \
  ca.key ca.crt \
  kube-api-server.key kube-api-server.crt \
  service-accounts.key service-accounts.crt \
  root@server:~/

ssh server ls -l /root
```

### ch5 Generating Kubernetes Configuration Files for Authentication
```sh
# kubelet 
for host in node-0 node-1; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-credentials system:node:${host} \
    --client-certificate=${host}.crt \
    --client-key=${host}.key \
    --embed-certs=true \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${host} \
    --kubeconfig=${host}.kubeconfig

  kubectl config use-context default \
    --kubeconfig=${host}.kubeconfig
done
ls -l *.kubeconfig

# kube-proxy
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.crt \
    --client-key=kube-proxy.key \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-proxy.kubeconfig

# kube-contorl-manager
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.crt \
    --client-key=kube-controller-manager.key \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default \
    --kubeconfig=kube-controller-manager.kubeconfig

# kube-scheduler
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.crt \
    --client-key=kube-scheduler.key \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default \
    --kubeconfig=kube-scheduler.kubeconfig

# admin k8s config file
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

kubectl config use-context default \
    --kubeconfig=admin.kubeconfig

ls -l *.kubeconfig

# Distribute the Kubernetes Configuration Files
for host in node-0 node-1; do
  ssh root@$host "mkdir /var/lib/{kube-proxy,kubelet}"

  scp kube-proxy.kubeconfig \
    root@$host:/var/lib/kube-proxy/kubeconfig \

  scp ${host}.kubeconfig \
    root@$host:/var/lib/kubelet/kubeconfig
done

ssh node-0 ls -l /var/lib/*/kubeconfig
-rw-------. 1 root root 10141 Jan 10 19:45 /var/lib/kubelet/kubeconfig
-rw-------. 1 root root 10171 Jan 10 19:45 /var/lib/kube-proxy/kubeconfig

# kube-controle-manager & kube-scheduler
scp admin.kubeconfig \
  kube-controller-manager.kubeconfig \
  kube-scheduler.kubeconfig \
  root@server:~/

ssh server ls -l /root/*.kubeconfig
-rw-------. 1 root root  9937 Jan 10 19:51 /root/admin.kubeconfig
-rw-------. 1 root root 10289 Jan 10 19:51 /root/kube-controller-manager.kubeconfig
-rw-------. 1 root root 10199 Jan 10 19:51 /root/kube-scheduler.kubeconfig
```

### ch6 Generating the Data Encryption Config and Key
```sh 
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
echo $ENCRYPTION_KEY
CsQGR7ysMqsl0ihoFK+f+ht3l3mLJnlKuY+IwNNt3Rg=

cat configs/encryption-config.yaml
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}

envsubst < configs/encryption-config.yaml \
  > encryption-config.yaml

cat encryption-config.yaml
scp encryption-config.yaml root@server:~/
ssh server ls -l /root/encryption-config.yaml
```

### ch7 Bootstrapping the etcd cluster
```sh
cat units/etcd.service | grep controller
  --name controller \
  --initial-cluster controller=http://127.0.0.1:2380 \

cat > units/etcd.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --initial-advertise-peer-urls http://127.0.0.1:2380 \\
  --listen-peer-urls http://127.0.0.1:2380 \\
  --listen-client-urls http://127.0.0.1:2379 \\
  --advertise-client-urls http://127.0.0.1:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${ETCD_NAME}=http://127.0.0.1:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat units/etcd.service | grep server
  --name server \
  --initial-cluster server=http://127.0.0.1:2380 \

scp \
  downloads/controller/etcd \
  downloads/client/etcdctl \
  units/etcd.service \
  root@server:~/

ssh root@server

mv etcd etcdctl /usr/local/bin/
chmod 700 /var/lib/etcd
cp ca.crt kube-api-server.key kube-api-server.crt \
    /etc/etcd/
mv etcd.service /etc/systemd/system/

# selinux로 인해 시작이 안되는 경우 비활성화
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

systemctl daemon-reload
systemctl enable etcd
systemctl start etcd

etcdctl member list
6702b0a34e2cfd39, started, server, http://127.0.0.1:2380, http://127.0.0.1:2379, false

ss -ntlp
LISTEN    0          4096               127.0.0.1:2380              0.0.0.0:*        users:(("etcd",pid=7260,fd=3))                                                     
LISTEN    0          4096               127.0.0.1:2379              0.0.0.0:*        users:(("etcd",pid=7260,fd=6))       

systemctl status etcd --no-pager

etcdctl member list -w table
etcdctl endpoint status -w table
exit 
```

### ch8 Bootstrapping the Kubernetes Control Plane
```sh
cat ca.conf | grep '\[kube-api-server_alt_names' -A2
[kube-api-server_alt_names]
IP.0  = 127.0.0.1
IP.1  = 10.32.0.1

cat units/kube-apiserver.service
cat << EOF > units/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --allow-privileged=true \\
  --apiserver-count=1 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.crt \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-servers=http://127.0.0.1:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.crt \\
  --kubelet-client-certificate=/var/lib/kubernetes/kube-api-server.crt \\
  --kubelet-client-key=/var/lib/kubernetes/kube-api-server.key \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-accounts.crt \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-accounts.key \\
  --service-account-issuer=https://server.kubernetes.local:6443 \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kube-api-server.crt \\
  --tls-private-key-file=/var/lib/kubernetes/kube-api-server.key \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat units/kube-apiserver.service

cat configs/kube-apiserver-to-kubelet.yaml ; echo
openssl x509 -in kube-api-server.crt -text -noout
cat units/kube-controller-manager.service ; echo

scp \
  downloads/controller/kube-apiserver \
  downloads/controller/kube-controller-manager \
  downloads/controller/kube-scheduler \
  downloads/client/kubectl \
  units/kube-apiserver.service \
  units/kube-controller-manager.service \
  units/kube-scheduler.service \
  configs/kube-scheduler.yaml \
  configs/kube-apiserver-to-kubelet.yaml \
  root@server:~/

ssh server ls -l /root
ssh root@server

mkdir -p /etc/kubernetes/config
mv kube-apiserver \
    kube-controller-manager \
    kube-scheduler kubectl \
    /usr/local/bin/

ls -l /usr/local/bin/kube-*

mkdir -p /var/lib/kubernetes/
mv ca.crt ca.key \
    kube-api-server.key kube-api-server.crt \
    service-accounts.key service-accounts.crt \
    encryption-config.yaml \
    /var/lib/kubernetes/
ls -l /var/lib/kubernetes/

mv kube-apiserver.service /etc/systemd/system/kube-apiserver.service
mv kube-controller-manager.kubeconfig /var/lib/kubernetes/
mv kube-controller-manager.service /etc/systemd/system/
mv kube-scheduler.kubeconfig /var/lib/kubernetes/
mv kube-scheduler.yaml /etc/kubernetes/config/
mv kube-scheduler.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable kube-apiserver kube-controller-manager kube-scheduler
systemctl start  kube-apiserver kube-controller-manager kube-scheduler


ss -tlp | grep kube
LISTEN 0      4096               *:sun-sr-https            *:*    users:(("kube-apiserver",pid=7582,fd=3))                
LISTEN 0      4096               *:10259                   *:*    users:(("kube-scheduler",pid=7591,fd=3))                
LISTEN 0      4096               *:10257                   *:*    users:(("kube-controller",pid=7586,fd=3))  


systemctl is-active kube-apiserver
systemctl status kube-apiserver --no-pager
journalctl -u kube-apiserver --no-pager

systemctl status kube-scheduler --no-pager
systemctl status kube-controller-manager --no-pager

kubectl cluster-info dump --kubeconfig admin.kubeconfig
kubectl cluster-info --kubeconfig admin.kubeconfig
Kubernetes control plane is running at https://127.0.0.1:6443

kubectl get node --kubeconfig admin.kubeconfig
kubectl get pod -A --kubeconfig admin.kubeconfig
kubectl get service,ep --kubeconfig admin.kubeconfig
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.32.0.1    <none>        443/TCP   2m50s

NAME                   ENDPOINTS        AGE
endpoints/kubernetes   10.0.2.15:6443   2m50s

kubectl get clusterroles --kubeconfig admin.kubeconfig
kubectl get clusterrolebindings --kubeconfig admin.kubeconfig
kubectl describe clusterroles system:kube-scheduler --kubeconfig admin.kubeconfig
kubectl describe clusterrolebindings system:kube-scheduler --kubeconfig admin.kubeconfig
```

RBAC for Kubelet Authorization
```sh
cat kube-apiserver-to-kubelet.yaml
kubectl apply -f kube-apiserver-to-kubelet.yaml \
  --kubeconfig admin.kubeconfig

kubectl get clusterroles system:kube-apiserver-to-kubelet --kubeconfig admin.kubeconfig
kubectl get clusterrolebindings system:kube-apiserver --kubeconfig admin.kubeconfig

exit

curl -s -k --cacert ca.crt https://server.kubernetes.local:6443/version | jq
{
  "major": "1",
  "minor": "35",
  "emulationMajor": "1",
  "emulationMinor": "35",
  "minCompatibilityMajor": "1",
  "minCompatibilityMinor": "34",
  "gitVersion": "v1.35.0",
  "gitCommit": "66452049f3d692768c39c797b21b793dce80314e",
  "gitTreeState": "clean",
  "buildDate": "2025-12-17T12:32:07Z",
  "goVersion": "go1.25.5",
  "compiler": "gc",
  "platform": "linux/arm64"
}
```

### ch9 Bootstrapping the Kubernetes Worker Nodes
```sh
cat configs/10-bridge.conf | jq
cat configs/kubelet-config.yaml | yq eval

for host in node-0 node-1; do
  SUBNET=$(grep $host machines.txt | cut -d " " -f 4)
  sed "s|SUBNET|$SUBNET|g" \
    configs/10-bridge.conf > 10-bridge.conf 

  sed "s|SUBNET|$SUBNET|g" \
    configs/kubelet-config.yaml > kubelet-config.yaml

  scp 10-bridge.conf kubelet-config.yaml \
  root@$host:~/
done

ssh node-0 ls -l /root
ssh node-1 ls -l /root

cat configs/99-loopback.conf ; echo
cat configs/containerd-config.toml ; echo
cat configs/kube-proxy-config.yaml ; echo
cat units/containerd.service
cat units/kubelet.service
cat units/kube-proxy.service

for HOST in node-0 node-1; do
  scp \
    downloads/worker/* \
    downloads/client/kubectl \
    configs/99-loopback.conf \
    configs/containerd-config.toml \
    configs/kube-proxy-config.yaml \
    units/containerd.service \
    units/kubelet.service \
    units/kube-proxy.service \
    root@${HOST}:~/
done

for HOST in node-0 node-1; do
  scp \
    downloads/cni-plugins/* \
    root@${HOST}:~/cni-plugins/
done

ssh node-0 ls -l /root
ssh node-1 ls -l /root
ssh node-0 ls -l /root/cni-plugins
ssh node-1 ls -l /root/cni-plugins

 
ssh root@node-1 #  node-1
dnf -y update
dnf -y install socat conntrack ipset tar

# 미출력 시 swaaoff
swapon --show

mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

mv crictl kube-proxy kubelet runc /usr/local/bin/
mv containerd containerd-shim-runc-v2 containerd-stress /bin/
mv cni-plugins/* /opt/cni/bin/
mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/

# 구성하지 않음 
# lsmod | grep netfilter
# modprobe br-netfilter
# echo "br-netfilter" >> /etc/modules-load.d/modules.conf
# lsmod | grep netfilter
# echo "net.bridge.bridge-nf-call-iptables = 1"  >> /etc/sysctl.d/kubernetes.conf
# echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/kubernetes.conf
# sysctl -p /etc/sysctl.d/kubernetes.conf

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# 값이 1이어야 한다.
sysctl net.ipv4.ip_forward
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#install-and-configure-prerequisites

#
mkdir -p /etc/containerd/
mv containerd-config.toml /etc/containerd/config.toml
mv containerd.service /etc/systemd/system/
mv kubelet-config.yaml /var/lib/kubelet/
mv kubelet.service /etc/systemd/system/
mv kube-proxy-config.yaml /var/lib/kube-proxy/
mv kube-proxy.service /etc/systemd/system/

cat /etc/containerd/config.toml ; echo

# etcd와 동일한 이유로 selinux에 의해 동작하지 않을 경우 비활성화
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

systemctl daemon-reload
systemctl enable containerd kubelet kube-proxy
systemctl start containerd kubelet kube-proxy

systemctl status kubelet --no-pager
systemctl status containerd --no-pager
systemctl status kube-proxy --no-pager

exit

ssh server "kubectl get nodes node-0 -o yaml --kubeconfig admin.kubeconfig" | yq eval
ssh server "kubectl get pod -A --kubeconfig admin.kubeconfig"
ssh server "kubectl get nodes -owide --kubeconfig admin.kubeconfig"
NAME     STATUS   ROLES    AGE    VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                  CONTAINER-RUNTIME
node-0   Ready    <none>   118s   v1.35.0   192.168.10.101   <none>        Rocky Linux 9.7 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.2.0
node-1   Ready    <none>   13s     v1.35.0   192.168.10.102   <none>        Rocky Linux 9.7 (Blue Onyx)   5.14.0-570.52.1.el9_6.aarch64   containerd://2.2.0
```

### ch10 Configuring kubectl for Remote Access
```sh
curl -s --cacert ca.crt https://server.kubernetes.local:6443/version | jq

kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443

kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key

kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

kubectl config use-context kubernetes-the-hard-way

kubectl version
Client Version: v1.35.0
Kustomize Version: v5.7.1
Server Version: v1.35.0

kubectl get nodes
NAME     STATUS   ROLES    AGE     VERSION
node-0   Ready    <none>   3h17m   v1.35.0
node-1   Ready    <none>   2m46s   v1.35.0
```

### ch11 Provisioning Pod Network Routes
```sh
{
  SERVER_IP=$(grep server machines.txt | cut -d " " -f 1)
  NODE_0_IP=$(grep node-0 machines.txt | cut -d " " -f 1)
  NODE_0_SUBNET=$(grep node-0 machines.txt | cut -d " " -f 4)
  NODE_1_IP=$(grep node-1 machines.txt | cut -d " " -f 1)
  NODE_1_SUBNET=$(grep node-1 machines.txt | cut -d " " -f 4)
}

echo $SERVER_IP $NODE_0_IP $NODE_0_SUBNET $NODE_1_IP $NODE_1_SUBNET

ssh root@server <<EOF
  ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}
  ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}
EOF

ssh root@node-0 <<EOF
  ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}
EOF

ssh root@node-1 <<EOF
  ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}
EOF

# before
ssh server ip -c route
default via 10.0.2.2 dev enp0s8 proto dhcp src 10.0.2.15 metric 100 
10.0.2.0/24 dev enp0s8 proto kernel scope link src 10.0.2.15 metric 100 
192.168.10.0/24 dev enp0s9 proto kernel scope link src 192.168.10.100 metric 101

# after 
ssh server ip -c route
default via 10.0.2.2 dev enp0s8 proto dhcp src 10.0.2.15 metric 100 
10.0.2.0/24 dev enp0s8 proto kernel scope link src 10.0.2.15 metric 100 
192.168.10.0/24 dev enp0s9 proto kernel scope link src 192.168.10.100 metric 101
10.200.0.0/24 via 192.168.10.101 dev enp0s9 
10.200.1.0/24 via 192.168.10.102 dev enp0s9 

ssh root@node-0 ip route
10.200.0.0/24 via 192.168.10.101 dev enp0s9 

ssh root@node-1 ip route
10.200.1.0/24 via 192.168.10.102 dev enp0s9 

```

## ch12 Smoke Test 

```sh
kubectl create secret generic kubernetes-the-hard-way \
  --from-literal="mykey=mydata"

ssh root@server \
    'etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C'
00000000  2f 72 65 67 69 73 74 72  79 2f 73 65 63 72 65 74  |/registry/secret|
00000010  73 2f 64 65 66 61 75 6c  74 2f 6b 75 62 65 72 6e  |s/default/kubern|
00000020  65 74 65 73 2d 74 68 65  2d 68 61 72 64 2d 77 61  |etes-the-hard-wa|
00000030  79 0a 6b 38 73 3a 65 6e  63 3a 61 65 73 63 62 63  |y.k8s:enc:aescbc|
00000040  3a 76 31 3a 6b 65 79 31  3a ad 9a 6e 69 02 e7 53  |:v1:key1:..ni..S|
00000050  50 88 99 34 80 88 0a 26  b2 3a 35 6a 9b fa d4 5d  |P..4...&.:5j...]|
00000060  5f ed 12 30 d5 f5 e1 d7  7e cb 94 56 68 00 f4 74  |_..0....~..Vh..t|
00000070  ef 45 78 96 a9 71 f1 da  6d a5 97 9f d4 8f bd 25  |.Ex..q..m......%|
00000080  23 82 18 7c 40 7e 76 6e  67 79 70 53 4b 38 3d 81  |#..|@~vngypSK8=.|
00000090  c8 ea 30 6b 22 d9 36 64  2b 39 f2 c4 27 f7 a0 45  |..0k".6d+9..'..E|
000000a0  d7 49 01 ad 49 db e9 ea  d6 ac 4f 17 aa 9c 0c dc  |.I..I.....O.....|
000000b0  b9 bf 11 71 c3 52 b4 bd  39 47 8d 77 a8 4c 48 bd  |...q.R..9G.w.LH.|
000000c0  6e da 02 df aa 65 a5 d6  77 3f 1e 57 30 92 eb 2a  |n....e..w?.W0..*|
000000d0  03 98 4a a8 5e 2c 53 73  96 11 0f 5f 6d 54 4d 6e  |..J.^,Ss..._mTMn|
000000e0  af 3c d9 77 77 9d 93 75  db d0 38 f1 ee f4 84 e9  |.<.ww..u..8.....|
000000f0  b8 34 19 35 c7 12 14 d0  43 96 e4 df 3f 69 2f c8  |.4.5....C...?i/.|
00000100  e1 72 85 65 91 b4 43 a8  6b 52 78 73 f4 e6 3a 5f  |.r.e..C.kRxs..:_|
00000110  7e 86 8d 2c 1b 0f b4 33  e6 68 70 97 0c 0a 75 c5  |~..,...3.hp...u.|
00000120  04 a7 b7 05 79 4a 25 b3  6c 32 fd 12 fd b0 4b 44  |....yJ%.l2....KD|
00000130  b9 bd 18 e5 49 25 4f f7  c2 22 60 b5 ab 68 90 b9  |....I%O.."`..h..|
00000140  e2 d7 fe 07 19 48 d0 8c  21 e7 8d 1b dc f4 2e 2a  |.....H..!......*|
00000150  45 3a e6 17 6d b8 92 3b  6d 0a                    |E:..m..;m.|
0000015a

kubectl create deployment nginx \
  --image=nginx:latest

kubectl get pods -l app=nginx
NAME                    READY   STATUS    RESTARTS   AGE
nginx-b6485fcbb-tcqfv   1/1     Running   0          14s

POD_NAME=$(kubectl get pods -l app=nginx \
  -o jsonpath="{.items[0].metadata.name}")

kubectl port-forward $POD_NAME 8080:80 &

curl --head http://127.0.0.1:8080
Handling connection for 8080
HTTP/1.1 200 OK
Server: nginx/1.29.4

kubectl logs $POD_NAME
127.0.0.1 - - [10/Jan/2026:15:03:25 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.76.1" "-"

kubectl exec -ti $POD_NAME -- nginx -v
nginx version: nginx/1.29.4

kubectl expose deployment nginx \
  --port 80 --type NodePort

NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{range .spec.ports[0]}{.nodePort}')

curl -I http://node-0:${NODE_PORT}
HTTP/1.1 200 OK
Server: nginx/1.29.4

kubectl get service,ep nginx
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME            TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
service/nginx   NodePort   10.32.0.218   <none>        80:31223/TCP   56s

NAME              ENDPOINTS       AGE
endpoints/nginx   10.200.0.2:80   56s
```

### ch13 Cleaning Up
```sh
exit
exit
vagrant destroy -f && rm -rf .vagrant
```

https://docs.rockylinux.org/10/labs/kubernetes-the-hard-way/lab0-README/   
https://containerd.io/releases/
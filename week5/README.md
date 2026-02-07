## k8s HA 및 버전 업그레이드
> Cloudnet@ k8s Deploy 5주차 스터디를 진행하며 정리한 글입니다.

서버 구성

| NAME | Description | CPU | RAM | NIC1 | NIC2 | Init Script |
| --- | --- | --- | --- | --- | --- | --- |
| **admin-lb** | kubespary 실행, API LB | 2 | 1GB | 10.0.2.15 | **192.168.10.10** | admin-lb.sh |
| **k8s-node1** | K8S ControlPlane | 4 | 2GB | 10.0.2.15 | **192.168.10.11** | init-cfg.sh |
| **k8s-node2** | K8S ControlPlane | 4 | 2GB | 10.0.2.15 | **192.168.10.12** | init-cfg.sh |
| **k8s-node3** | K8S ControlPlane | 4 | 2GB | 10.0.2.15 | **192.168.10.13** | init-cfg.sh |
| **k8s-node4** | K8S Worker | 4 | 2GB | 10.0.2.15 | **192.168.10.14** | init-cfg.sh |
| **k8s-node5** | K8S Worker | 4 | 2GB | 10.0.2.15 | **192.168.10.15** | init-cfg.sh |

### k8s 초기 설정 
처음 구성은 admin-lb, CP 3대와 워커 노드 1대로 구성되어있다. 
```sh
vagrant up
vagrant status
vagrant ssh admin-lb
vagrant destroy -f && rm -rf .vagrant

ip -c -br -4 addr
lo               UNKNOWN        127.0.0.1/8 
enp0s3           UP             10.0.2.15/24
enp0s9           UP             192.168.10.10/24

# 네임서버 검증
cat /etc/hosts
192.168.10.10 k8s-api-srv.admin-lb.com admin-lb
192.168.10.11 k8s-node1
192.168.10.12 k8s-node2
192.168.10.13 k8s-node3
192.168.10.14 k8s-node4
192.168.10.15 k8s-node5

# 각 서버간 통신 확인
for i in {0..5}; do echo ">> k8s-node$i <<"; ssh 192.168.10.1$i hostname; echo; done
>> k8s-node0 <<
admin-lb
>> k8s-node1 <<
k8s-node1
>> k8s-node2 <<
k8s-node2
>> k8s-node3 <<
k8s-node3
e4 <<
k8s-node4
>> k8s-node5 <<
k8s-node5

for i in {1..5}; do echo ">> k8s-node$i <<"; ssh k8s-node$i hostname; echo; done
>> k8s-node1 <<
k8s-node1
>> k8s-node2 <<
k8s-node2
>> k8s-node3 <<
k8s-node3
>> k8s-node4 <<
k8s-node4
>> k8s-node5 <<
k8s-node5


# nfs 서버 상태 확인 
systemctl status nfs-server --no-pager
tree /srv/nfs/share/
/srv/nfs/share/

# nfs 설정 확인
exportfs -rav
exporting *:/srv/nfs/share

# nfs 설정 확인
cat /etc/exports
/srv/nfs/share *(rw,async,no_root_squash,no_subtree_check)

# haproxy 설정 확인
# :6443 요청 시 컨트롤플레인 1 ~ 3에 요청 전달
cat /etc/haproxy/haproxy.cfg
frontend k8s-api
    bind *:6443
    mode tcp
    option tcplog
    default_backend k8s-api-backend

backend k8s-api-backend
    mode tcp
    option tcp-check
    option log-health-checks
    timeout client 3h
    timeout server 3h
    balance roundrobin
    server k8s-node1 192.168.10.11:6443 check check-ssl verify none inter 10000
    server k8s-node2 192.168.10.12:6443 check check-ssl verify none inter 10000
    server k8s-node3 192.168.10.13:6443 check check-ssl verify none inter 10000

# haproxy 상태 확인 
systemctl status haproxy.service --no-pager
journalctl -u haproxy.service --no-pager

# haproxy 포트 확인 8405 메트릭, 9000 haproxy 통계 페이지
ss -tnlp | grep haproxy
LISTEN 0      3000         0.0.0.0:8405       0.0.0.0:*    users:(("haproxy",pid=5375,fd=9))        
LISTEN 0      3000         0.0.0.0:6443       0.0.0.0:*    users:(("haproxy",pid=5375,fd=7))        
LISTEN 0      3000         0.0.0.0:9000       0.0.0.0:*    users:(("haproxy",pid=5375,fd=8))        

open http://192.168.10.10:9000/haproxy_stats
open http://192.168.10.10:8405/metrics

# 태그 정보 확인
git describe --tags
v2.29.1

git --no-pager tag
v2.29.0
v2.29.1
v2.3.0
v2.30.0
...

cd /root/kubespray/

# ansible 인벤토리 구성 확인
cat /root/kubespray/inventory/mycluster/inventory.ini

tree inventory/mycluster/

# 각 노드에 적용되는 변수 조회
ansible-inventory -i /root/kubespray/inventory/mycluster/inventory.ini --list
        "k8s-node1": {
                "allow_unsupported_distribution_setup": false,
                "ansible_host": "192.168.10.11",
                "bin_dir": "/usr/local/bin",
                "docker_bin_dir": "/usr/bin",
                "docker_container_storage_setup": false,
                "docker_daemon_graph": "/var/lib/docker",
                "docker_dns_servers_strict": false,
                "docker_iptables_enabled": "false",
                "docker_log_opts": "--log-opt max-size=50m --log-opt max-file=5",
                "docker_rpm_keepcache": 1,
                "etcd_data_dir": "/var/lib/etcd",
                "etcd_deployment_type": "host",
                "etcd_member_name": "etcd1",
                "ip": "192.168.10.11",
                "kube_webhook_token_auth": false,
                "kube_webhook_token_auth_url_skip_tls_verify": false,
                "loadbalancer_apiserver_healthcheck_port": 8081,
                "loadbalancer_apiserver_port": 6443,
                "no_proxy_exclude_workers": false,
                "ntp_enabled": false,
                "ntp_manage_config": false,
                "ntp_servers": [
                    "0.pool.ntp.org iburst",
                    "1.pool.ntp.org iburst",
                    "2.pool.ntp.org iburst",
                    "3.pool.ntp.org iburst"
                ],
                "unsafe_show_logs": false
            },
...

# 모드 역할 그래프 형태 출력
ansible-inventory -i /root/kubespray/inventory/mycluster/inventory.ini --graph
@all:
  |--@ungrouped:
  |--@etcd:
  |  |--@kube_control_plane:
  |  |  |--k8s-node1
  |  |  |--k8s-node2
  |  |  |--k8s-node3
  |--@kube_node:
  |  |--k8s-node4

# k8s_clusetr.yml
# root 사용자 변경, flannel 적용, kube_proxy, iptables, nodelocaldns 비활성화 후 확인
sed -i 's|kube_owner: kube|kube_owner: root|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|kube_network_plugin: calico|kube_network_plugin: flannel|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|kube_proxy_mode: ipvs|kube_proxy_mode: iptables|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|enable_nodelocaldns: true|enable_nodelocaldns: false|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
grep -iE 'kube_owner|kube_network_plugin:|kube_proxy_mode|enable_nodelocaldns:' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

## coredns autoscaler 비활성화 
echo "enable_dns_autoscaler: false" >> inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
echo "flannel_interface: enp0s9" >> inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml
grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml

# flannel 인터페이스 지정
echo "flannel_interface: enp0s8" >> inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml
grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml

# 메트릭서버 활성화 및 요청 리소스 설정
sed -i 's|metrics_server_enabled: false|metrics_server_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
echo "metrics_server_requests_cpu: 25m"     >> inventory/mycluster/group_vars/k8s_cluster/addons.yml
echo "metrics_server_requests_memory: 16Mi" >> inventory/mycluster/group_vars/k8s_cluster/addons.yml
grep -iE 'metrics_server_enabled:' inventory/mycluster/group_vars/k8s_cluster/addons.yml

# k8s 지원 버전 체크섬
cat roles/kubespray_defaults/vars/main/checksums.yml | grep -i kube -A40

# 약 7분 소요
ANSIBLE_FORCE_COLOR=true ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml -e kube_version="1.32.9" | tee kubespray_install.log

# 설치 로그 및 fact 캐시 확인
more kubespray_install.log
tree -L 2 /tmp
├── k8s-node1
├── k8s-node2
├── k8s-node3
├── k8s-node4

# 컨트롤 플레인과 워커노드의 /tmp/releases 차이 확인
ssh k8s-node1 tree /tmp/releases
/tmp/releases
├── cni-plugins-linux-amd64-1.8.0.tgz
├── containerd-2.1.5-linux-amd64.tar.gz
├── containerd-rootless-setuptool.sh
├── containerd-rootless.sh
├── crictl
├── crictl-1.32.0-linux-amd64.tar.gz
├── etcd-3.5.25-linux-amd64.tar.gz
├── etcd-v3.5.25-linux-amd64
│   ├── Documentation
│   │   ├── dev-guide
│   │   │   └── apispec
│   │   │       └── swagger
│   │   │           ├── rpc.swagger.json
│   │   │           ├── v3election.swagger.json
│   │   │           └── v3lock.swagger.json
│   │   └── README.md
│   ├── etcd
│   ├── etcdctl
│   ├── etcdutl
│   ├── README-etcdctl.md
│   ├── README-etcdutl.md
│   ├── README.md
│   └── READMEv2-etcdctl.md
├── images
├── kubeadm-1.32.9-amd64
├── kubectl-1.32.9-amd64
├── kubelet-1.32.9-amd64
├── nerdctl
├── nerdctl-2.1.6-linux-amd64.tar.gz
└── runc-1.3.4.amd64
7 directories, 24 files

ssh k8s-node4 tree /tmp/releases
/tmp/releases
├── cni-plugins-linux-amd64-1.8.0.tgz
├── containerd-2.1.5-linux-amd64.tar.gz
├── containerd-rootless-setuptool.sh
├── containerd-rootless.sh
├── crictl
├── crictl-1.32.0-linux-amd64.tar.gz
├── images
├── kubeadm-1.32.9-amd64
├── kubelet-1.32.9-amd64
├── nerdctl
├── nerdctl-2.1.6-linux-amd64.tar.gz
└── runc-1.3.4.amd64
2 directories, 11 files

# 커널 파라미터 확인
# 결과적으로 모든 노드의 커널 파라미터는 동일한 것을 확인했다. 
ssh k8s-node1 grep "^[^#]" /etc/sysctl.conf
ssh k8s-node4 grep "^[^#]" /etc/sysctl.conf
net.ipv4.ip_forward=1
kernel.keys.root_maxbytes=25000000
kernel.keys.root_maxkeys=1000000
kernel.panic=10
kernel.panic_on_oops=1
vm.overcommit_memory=1
vm.panic_on_oom=0
net.ipv4.ip_local_reserved_ports=30000-32767
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-arptables=1
net.bridge.bridge-nf-call-ip6tables=1

# etcd 백업 확인
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i tree /var/backups; echo; done
/var/backups
└── etcd-2026-02-05_11:19:31
    ├── member
    │   ├── snap
    │   │   └── db
    │   └── wal
    │       └── 0000000000000000-0000000000000000.wal
    └── snapshot.db
5 directories, 3 files

# api 호출
cat /etc/hosts
192.168.10.11 k8s-node1
192.168.10.12 k8s-node2
192.168.10.13 k8s-node3

# ip 동작 확인
for i in {1..3}; do echo ">> k8s-node$i <<"; curl -sk https://192.168.10.1$i:6443/version | grep Version; echo; done

# 도메인 동작 확인
for i in {1..3}; do echo ">> k8s-node$i <<"; curl -sk https://k8s-node$i:6443/version | grep Version; echo; done

# 컨트롤플레인 apiserver 요청 확인
# 모든 kubeconfg가 자기 자신을 호출한다.
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i kubectl cluster-info -v=6; echo; done
I0205 11:40:12.383682   28861 loader.go:402] Config loaded from file:  /root/.kube/config
Kubernetes control plane is running at https://127.0.0.1:6443

# kubeconifg 복사 
mkdir /root/.kube
scp k8s-node1:/root/.kube/config /root/.kube/

cat /root/.kube/config | grep server
    server: https://127.0.0.1:6443

# kubeconfig에 설정된 주소는 localhost이다. 즉 haproxy -> k8s 컨트롤플레인 1 ~ 3에 분산 전달하고 있다.
# 테스트를 위해 1대의 컨트롤 플레인 api-server 주소로 명시하여 구성한다.
sed -i 's/127.0.0.1/192.168.10.11/g' /root/.kube/config

kubectl get node -owide -v=6
I0201 14:42:31.785003   13881 loader.go:402] Config loaded from file:  /root/.kube/config
I0205 11:44:46.395830   14586 round_trippers.go:560] GET https://192.168.10.11:6443/apis?timeout=32s 200 OK in 5 milliseconds
NAME        STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                        KERNEL-VERSION                 CONTAINER-RUNTIME
k8s-node1   Ready    control-plane   25m   v1.32.9   192.168.10.11   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.x86_64   containerd://2.1.5
k8s-node2   Ready    control-plane   25m   v1.32.9   192.168.10.12   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.x86_64   containerd://2.1.5
k8s-node3   Ready    control-plane   24m   v1.32.9   192.168.10.13   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.x86_64   containerd://2.1.5
k8s-node4   Ready    <none>          23m   v1.32.9   192.168.10.14   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.x86_64   containerd://2.1.5

ansible-inventory -i /root/kubespray/inventory/mycluster/inventory.ini --graph
@all:
  |--@ungrouped:
  |--@etcd:
  |  |--@kube_control_plane:
  |  |  |--k8s-node1
  |  |  |--k8s-node2
  |  |  |--k8s-node3
  |--@kube_node:
  |  |--k8s-node4

# 테인트 비교
# 컨트롤플레인에는 파드가 스케쥴링되지 않는다.
kubectl describe node | grep -E 'Name:|Taints'
Name:               k8s-node1
Taints:             node-role.kubernetes.io/control-plane:NoSchedule
Name:               k8s-node2
Taints:             node-role.kubernetes.io/control-plane:NoSchedule
Name:               k8s-node3
Taints:             node-role.kubernetes.io/control-plane:NoSchedule
Name:               k8s-node4
Taints:             <none>

# 전체 파드, 동일한 내용은 일부 정리했다.
# 이중 nginx-proxy가 있는데 nginx-prxoy는 워커노드에서 컨트롤 플레인 api-server에 요청을 전달하는 client side lb이다. 현재는 워커 노드 1대라 1개가 존재한다.
kubectl get pod -A
NAMESPACE     NAME                                READY   STATUS    RESTARTS   AGE
kube-system   coredns-664b99d7c7-77mtr            1/1     Running   0          7m1s # 2개 
kube-system   kube-apiserver-k8s-node1            1/1     Running   1          8m13s # node 1 ~ node 3
kube-system   kube-controller-manager-k8s-node1   1/1     Running   2          8m13s # node 1 ~ node 3
kube-system   kube-flannel-ds-arm64-lcnrf         1/1     Running   0          7m12s # 4개
kube-system   kube-proxy-5fjlq                    1/1     Running   0          7m26s # 4개
kube-system   kube-scheduler-k8s-node1            1/1     Running   1          8m13s # node 1 ~ node 3
kube-system   metrics-server-65fdf69dcb-p4c46     1/1     Running   0          6m56s
kube-system   nginx-proxy-k8s-node4               1/1     Running   0          7m27s # 1개 

# 노드 cidr 확인
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
k8s-node1       10.233.64.0/24
k8s-node2       10.233.65.0/24
k8s-node3       10.233.66.0/24
k8s-node4       10.233.67.0/24

# etcd 멤버 목록 확인
ssh k8s-node1 etcdctl.sh member list -w table
+------------------+---------+-------+----------------------------+----------------------------+------------+
|        ID        | STATUS  | NAME  |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-------+----------------------------+----------------------------+------------+
|  8b0ca30665374b0 | started | etcd3 | https://192.168.10.13:2380 | https://192.168.10.13:2379 |      false |
| 2106626b12a4099f | started | etcd2 | https://192.168.10.12:2380 | https://192.168.10.12:2379 |      false |
| c6702130d82d740f | started | etcd1 | https://192.168.10.11:2380 | https://192.168.10.11:2379 |      false |
+------------------+---------+-------+----------------------------+----------------------------+------------+

# 서버 접속 후 etcd 엔드포인트 상태
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i etcdctl.sh endpoint status -w table; echo; done
>> k8s-node1 <<
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | c6702130d82d740f |  3.5.25 |  5.3 MB |      true |      false |         5 |       2590 |               2590 |        |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
>> k8s-node2 <<
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | 2106626b12a4099f |  3.5.25 |  5.3 MB |     false |      false |         5 |       2591 |               2591 |        |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
>> k8s-node3 <<
+----------------+-----------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |       ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+-----------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | 8b0ca30665374b0 |  3.5.25 |  5.3 MB |     false |      false |         5 |       2591 |               2591 |        |
+----------------+-----------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+

k9s 

# 자동완성
source <(kubectl completion bash)
alias k=kubectl
alias kc=kubecolor
complete -F __start_kubectl k
echo 'source <(kubectl completion bash)' >> /etc/profile
echo 'alias k=kubectl' >> /etc/profile
echo 'alias kc=kubecolor' >> /etc/profile
echo 'complete -F __start_kubectl k' >> /etc/profile
```

### ansible 변수 우선순위 확인 [^1]

```sh
# k8s 클러스터 공용 변수 설정
inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# 특정 노드 설정 적용
inventory/mycluster/host_vars/k8s-ctr1.yml

# playbook에 선언된 경우
cat playbooks/cluster.yml |grep -i vars -A3 -B1
- name: Install etcd
  vars:
    etcd_cluster_setup: true
    etcd_events_cluster_setup: "{{ etcd_events_cluster_enabled }}"
  import_playbook: install_etcd.yml

# autoscaler 설정 조회 
# role의 기본 설정은 true이고 group_vars에는 false이다. ansible 변수 우선순위에 따라 group_vars의 값이 적용된다.
grep -Rni "autoscaler:" inventory/mycluster/ playbooks/ roles/ -A2 -B1
roles/kubespray_defaults/defaults/main/main.yml:131:enable_dns_autoscaler: true
inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml:373:enable_dns_autoscaler: false

# api-server 설정 확인
ssh k8s-node1 cat /etc/kubernetes/manifests/kube-apiserver.yaml
  - command:
    - kube-apiserver
    - --advertise-address=192.168.10.11
    - --allow-privileged=true
    - --anonymous-auth=True
    - --apiserver-count=3
    - --authorization-mode=Node,RBAC
    - '--bind-address=::'
    - --client-ca-file=/etc/kubernetes/ssl/ca.crt
    - --default-not-ready-toleration-seconds=300
    - --default-unreachable-toleration-seconds=300
    - --enable-admission-plugins=NodeRestriction
    - --enable-aggregator-routing=False
    - --enable-bootstrap-token-auth=true
    - --endpoint-reconciler-type=lease
    - --etcd-cafile=/etc/ssl/etcd/ssl/ca.pem
    - --etcd-certfile=/etc/ssl/etcd/ssl/node-k8s-node1.pem
    - --etcd-compaction-interval=5m0s
    - --etcd-keyfile=/etc/ssl/etcd/ssl/node-k8s-node1-key.pem
    - --etcd-servers=https://192.168.10.11:2379,https://192.168.10.12:2379,https://192.168.10.13:2379
    - --event-ttl=1h0m0s
    - --kubelet-client-certificate=/etc/kubernetes/ssl/apiserver-kubelet-client.crt
    - --kubelet-client-key=/etc/kubernetes/ssl/apiserver-kubelet-client.key
    - --kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP
    - --profiling=False
    - --proxy-client-cert-file=/etc/kubernetes/ssl/front-proxy-client.crt
    - --proxy-client-key-file=/etc/kubernetes/ssl/front-proxy-client.key
    - --request-timeout=1m0s
    - --requestheader-allowed-names=front-proxy-client
    - --requestheader-client-ca-file=/etc/kubernetes/ssl/front-proxy-ca.crt
    - --requestheader-extra-headers-prefix=X-Remote-Extra-
    - --requestheader-group-headers=X-Remote-Group
    - --requestheader-username-headers=X-Remote-User
    - --secure-port=6443
    - --service-account-issuer=https://kubernetes.default.svc.cluster.local
    - --service-account-key-file=/etc/kubernetes/ssl/sa.pub
    - --service-account-lookup=True
    - --service-account-signing-key-file=/etc/kubernetes/ssl/sa.key
    - --service-cluster-ip-range=10.233.0.0/18
    - --service-node-port-range=30000-32767
    - --storage-backend=etcd3
    - --tls-cert-file=/etc/kubernetes/ssl/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/ssl/apiserver.key

# lease 정보 확인
# api-server 할성화 여부와 컨트롤 플레인 컴포넌트의 리더에 대한 정보를 출력한다.
kubectl get lease -n kube-system
NAME                                   HOLDER                                                                      AGE
apiserver-3jsrenrspxlfjr2cvxzde6qwdi   apiserver-3jsrenrspxlfjr2cvxzde6qwdi_d301a69d-f7e1-4c59-9993-44303cad5ff7   49m      
apiserver-syplgv2uz3ssgciixtnxs4xeza   apiserver-syplgv2uz3ssgciixtnxs4xeza_c23935ac-6e9e-4480-9a0d-14184699aa9b   48m      
apiserver-z2kpjb5k5ch6lznxmv3gnpujmy   apiserver-z2kpjb5k5ch6lznxmv3gnpujmy_9321aab5-a8e2-49b7-953a-4f0334ee78b4   48m      
kube-controller-manager                k8s-node3_7a66d5e4-4b2f-43fa-bfeb-d5bcc7a141ab                              49m      
kube-scheduler                         k8s-node1_ef6c2ef5-9c6e-4c33-b9a9-a01b17cf2dfe                              49m  

# kube-controll-manager 설정 확인
ssh k8s-node1 cat /etc/kubernetes/manifests/kube-controller-manager.yaml
  - command:
    - kube-controller-manager
    - --allocate-node-cidrs=true
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - '--bind-address=::'
    - --client-ca-file=/etc/kubernetes/ssl/ca.crt
    - --cluster-cidr=10.233.64.0/18
    - --cluster-name=cluster.local
    - --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.crt
    - --cluster-signing-key-file=/etc/kubernetes/ssl/ca.key
    - --configure-cloud-routes=false
    - --controllers=*,bootstrapsigner,tokencleaner
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --leader-elect=true
    - --leader-elect-lease-duration=15s
    - --leader-elect-renew-deadline=10s
    - --node-cidr-mask-size-ipv4=24
    - --node-monitor-grace-period=40s
    - --node-monitor-period=5s
    - --profiling=False
    - --requestheader-client-ca-file=/etc/kubernetes/ssl/front-proxy-ca.crt
    - --root-ca-file=/etc/kubernetes/ssl/ca.crt
    - --service-account-private-key-file=/etc/kubernetes/ssl/sa.key
    - --service-cluster-ip-range=10.233.0.0/18
    - --terminated-pod-gc-threshold=12500
    - --use-service-account-credentials=true

# kube-scheduler 설정 확인
ssh k8s-node1 cat /etc/kubernetes/manifests/kube-scheduler.yaml
  - command:
    - kube-scheduler
    - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
    - --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
    - '--bind-address=::'
    - --config=/etc/kubernetes/kubescheduler-config.yaml
    - --kubeconfig=/etc/kubernetes/scheduler.conf
    - --leader-elect=true
    - --profiling=False

# 인증서 확인
# 컨트롤 플레인 1에만 admin 설정이 존재한다.
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i ls -l /etc/kubernetes/super-admin.conf ; echo; done
>> k8s-node1 <<
-rw-------. 1 root root 5693 Feb  5 11:20 /etc/kubernetes/super-admin.conf
>> k8s-node2 <<
ls: cannot access '/etc/kubernetes/super-admin.conf': No such file or directory
>> k8s-node3 <<
ls: cannot access '/etc/kubernetes/super-admin.conf': No such file or directory

# 인증서 확인
# ca는 10년, 다른 인증서 기한은 1년이다.
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i kubeadm certs check-expiration ; echo; done
>> k8s-node1 <<
[check-expiration] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[check-expiration] Use 'kubeadm init phase upload-config --config your-config.yaml' to re-upload it.

W0205 14:23:40.804062   68399 utils.go:69] The recommended value for "clusterDNS" in "KubeletConfiguration" is: [10.233.0.10]; the provided value is: [10.233.0.3]
CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Feb 05, 2027 02:20 UTC   364d            ca                      no
apiserver                  Feb 05, 2027 02:20 UTC   364d            ca                      no
apiserver-kubelet-client   Feb 05, 2027 02:20 UTC   364d            ca                      no
controller-manager.conf    Feb 05, 2027 02:20 UTC   364d            ca                      no
front-proxy-client         Feb 05, 2027 02:20 UTC   364d            front-proxy-ca          no
scheduler.conf             Feb 05, 2027 02:20 UTC   364d            ca                      no
super-admin.conf           Feb 05, 2027 02:20 UTC   364d            ca                      no

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Feb 03, 2036 02:20 UTC   9y              no
front-proxy-ca          Feb 03, 2036 02:20 UTC   9y              no

# nginx 파드에서 coredns service ip 확인
kubectl exec -it -n kube-system nginx-proxy-k8s-node4 -- cat /etc/resolv.conf
search kube-system.svc.cluster.local svc.cluster.local cluster.local default.svc.cluster.local
nameserver 10.233.0.3
options ndots:5

# 앞서 확인한 dns 주소와 일치한다
kubectl get svc -n kube-system coredns
NAME      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
coredns   ClusterIP   10.233.0.3   <none>        53/UDP,53/TCP,9153/TCP   48m

# coredns 설정 확인
kubectl get cm -n kube-system kubelet-config -o yaml | grep clusterDNS -A2
   clusterDNS:
    - 10.233.0.3
    clusterDomain: cluster.local

#kubeadm으로 배포시에는 10.96.0.0/16에서 10번째 ip를 할당받는다.
#kubectl get svc,ep -n kube-system
#service/kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   4h50m

# 컨트롤플레인 1의 dns 설정 조회
ssh k8s-node1 cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local
nameserver 10.233.0.3
nameserver 10.0.2.3
options ndots:2 timeout:2 attempts:2

# 반면에 아직 k8s에 편입되지 않은 노드의 dns 설정은 기본 dns 설정으로만 구성되어 있따.
ssh k8s-node5 cat /etc/resolv.conf
nameserver 10.0.2.3

# kuabeadm 설정 확인
kubectl get cm -n kube-system kubeadm-config -o yaml
    apiVersion: kubeadm.k8s.io/v1beta4
    caCertificateValidityPeriod: 87600h0m0s
    certificateValidityPeriod: 8760h0m0s
    certificatesDir: /etc/kubernetes/ssl
    clusterName: cluster.local
    controlPlaneEndpoint: 192.168.10.11:6443
   dns:
      disabled: true
      imageRepository: registry.k8s.io/coredns
      imageTag: v1.11.3
    encryptionAlgorithm: RSA-2048
    etcd:
      external:
        caFile: /etc/ssl/etcd/ssl/ca.pem
        certFile: /etc/ssl/etcd/ssl/node-k8s-node1.pem
        endpoints:
        - https://192.168.10.11:2379
        - https://192.168.10.12:2379
        - https://192.168.10.13:2379
        keyFile: /etc/ssl/etcd/ssl/node-k8s-node1-key.pem
    imageRepository: registry.k8s.io
    kind: ClusterConfiguration
    kubernetesVersion: v1.32.9
    networking:
      dnsDomain: cluster.local
      podSubnet: 10.233.64.0/18
      serviceSubnet: 10.233.0.0/18

kubectl get csr
NAME        AGE    SIGNERNAME                                    REQUESTOR                 REQUESTEDDURATION   CONDITION
csr-bz27m   179m   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:7auy9c   <none>              Approved,Issued
csr-dsmdj   3h2m   kubernetes.io/kube-apiserver-client-kubelet   system:node:k8s-node1     <none>              Approved,Issued
csr-hm624   3h1m   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:fzeg2q   <none>              Approved,Issued
csr-hxq69   3h1m   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:8i24r6   <none>              Approved,Issued
```


### 컨트롤 플레인 
```sh
# api-server ip 확인 
kubectl describe pod -n kube-system kube-apiserver-k8s-node1 | grep -E 'address|secure-port'
Annotations:          kubeadm.kubernetes.io/kube-apiserver.advertise-address.endpoint: 192.168.10.11:6443
      --advertise-address=192.168.10.11
      --bind-address=::
      --kubelet-preferred-address-types=InternalDNS,InternalIP,Hostname,ExternalDNS,ExternalIP
      --secure-port=6443

ssh k8s-node1 ss -tnlp | grep 6443
LISTEN 0      4096               *:6443             *:*    users:(("kube-apiserver",pid=27533,fd=3))

ssh k8s-node1 ip -br -4 addr
lo               UNKNOWN        127.0.0.1/8 
enp0s3           UP             10.0.2.15/24
enp0s8           UP             192.168.10.11/24
flannel.1        UNKNOWN        10.233.64.0/32

# localhost, ip, domain 전부 호출이 가능하다
ssh k8s-node1 curl -sk https://127.0.0.1:6443/version | grep gitVersion
ssh k8s-node1 curl -sk https://10.0.2.15:6443/version | grep gitVersion
ssh k8s-node1 curl -sk https://192.168.10.11:6443/version | grep gitVersion
ssh k8s-node1 curl -sk https://k8s-node1:6443/version | grep gitVersion

ssh k8s-node1 cat /etc/kubernetes/admin.conf | grep server
    server: https://127.0.0.1:6443

ssh k8s-node1 cat /etc/kubernetes/super-admin.conf | grep server
    server: https://192.168.10.11:6443

# kubelet 설정 localhost로 자기자신을 호출한다.
ssh k8s-node1 cat /etc/kubernetes/kubelet.conf | grep server
    server: https://127.0.0.1:6443

# kube-proxy localhost 호출
k get cm -n kube-system kube-proxy -o yaml | grep server
        server: https://127.0.0.1:6443

# 컨트롤매니저, 스케쥴러도 마찬가지로 localhost 통신
ssh k8s-node1 cat /etc/kubernetes/controller-manager.conf | grep server
    server: https://127.0.0.1:6443

ssh k8s-node1 cat /etc/kubernetes/scheduler.conf | grep server
    server: https://127.0.0.1:6443
```


### worker node
```sh
# 워커 노드 파드 조회
ssh k8s-node4 crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                               NAMESPACE
de6c3216b53fb       b9e1e3849e070       3 hours ago         Running             metrics-server      0                   a40200b7bb130       metrics-server-65fdf69dcb-pbsjp   kube-system
233a58a89a105       c69fa2e9cbf5f       3 hours ago         Running             coredns             0                   56fbd140e6da7       coredns-664b99d7c7-m96n5          kube-system
9c55a6efb325c       3475d115f79b6       3 hours ago         Running             kube-flannel        1                   418b3fad22b4d       kube-flannel-2jhbm                kube-system
f538bb6828826       fa3fdca615a50       3 hours ago         Running             kube-proxy          0                   b42c93fc40b8b       kube-proxy-rrqgc                  kube-system
10b97b3e8bab7       c318e336065b1       3 hours ago         Running             nginx-proxy         0                   ee4993d84a921       nginx-proxy-k8s-node4             kube-system

# 워커노드의 nignx 설정 확인
ssh k8s-node4 cat /etc/nginx/nginx.conf
error_log stderr notice;

worker_processes 2;
worker_rlimit_nofile 130048;
worker_shutdown_timeout 10s;

events {
  multi_accept on;
  use epoll;
  worker_connections 16384;
}

stream {
  upstream kube_apiserver {
    least_conn;
    server 192.168.10.11:6443;
    server 192.168.10.12:6443;
    server 192.168.10.13:6443;
    }

  server {
    listen        127.0.0.1:6443;
    proxy_pass    kube_apiserver;
    proxy_timeout 10m;
    proxy_connect_timeout 1s;
  }
}

http {
  aio threads;
  aio_write on;
  tcp_nopush on;
  tcp_nodelay on;

  keepalive_timeout 5m;
  keepalive_requests 100;
  reset_timedout_connection on;
  server_tokens off;
  autoindex off;

  server {
    listen 8081;
    location /healthz {
      access_log off;
      return 200;
    }
    location /stub_status {
      stub_status on;
      access_log off;
    }
  }
  }

# nginx 헬스체크
ssh k8s-node4 curl -s localhost:8081/healthz -I
HTTP/1.1 200 OK
Server: nginx

# 워커노드의 k8s api-server 호출
ssh k8s-node4 curl -sk https://127.0.0.1:6443/version | grep Version
  "gitVersion": "v1.32.9",
  "goVersion": "go1.23.12",

# 포트 확인
ssh k8s-node4 ss -tnlp | grep nginx
LISTEN 0      511        127.0.0.1:6443       0.0.0.0:*    users:(("nginx",pid=15752,fd=5),("nginx",pid=15751,fd=5),("nginx",pid=15708,fd=5))
LISTEN 0      511          0.0.0.0:8081       0.0.0.0:*    users:(("nginx",pid=15752,fd=6),("nginx",pid=15751,fd=6),("nginx",pid=15708,fd=6))

# 워커노드의 kubelet 설정 확인
# kubelet -> nginx -> api-server 요청
ssh k8s-node4 cat /etc/kubernetes/kubelet.conf | grep server
    server: https://localhost:6443

# kubeoncifg 설정 조회
kubectl get cm -n kube-system kube-proxy -o yaml | grep 'kubeconfig.conf:' -A18
  kubeconfig.conf: |-
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        server: https://127.0.0.1:6443
      name: default
    contexts:
    - context:
        cluster: default
        namespace: default
        user: default
      name: default
    current-context: default
    users:
    - name: default
      user:
        tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token

# ansible의 nginx 생성 tastk 
tree roles/kubernetes/node/tasks/loadbalancer
roles/kubernetes/node/tasks/loadbalancer
├── haproxy.yml
├── kube-vip.yml
└── nginx-proxy.yml

# 총 5개의 task로 구성
# nginx dir 생성 후 nginx 템플릿 적용 후 서버 전달. 이후 스태틱파드로 생성
cat roles/kubernetes/node/tasks/loadbalancer/nginx-proxy.yml
- name: Nginx-proxy | Make nginx directory
  file:
    path: "{{ nginx_config_dir }}"
    state: directory
    mode: "0700"
    owner: root

- name: Nginx-proxy | Write nginx-proxy configuration
  template:
    src: "loadbalancer/nginx.conf.j2"
    dest: "{{ nginx_config_dir }}/nginx.conf"
    owner: root
    mode: "0755"
    backup: true

- name: Nginx-proxy | Get checksum from config
  stat:
    path: "{{ nginx_config_dir }}/nginx.conf"
    get_attributes: false
    get_checksum: true
    get_mime: false
  register: nginx_stat

- name: Nginx-proxy | Write static pod
  template:
    src: manifests/nginx-proxy.manifest.j2
    dest: "{{ kube_manifest_dir }}/nginx-proxy.yml"
    mode: "0640"

# nginx.conf 템플릿
cat roles/kubernetes/node/templates/loadbalancer/nginx.conf.j2
# nginx pod 템플릿
cat roles/kubernetes/node/templates/manifests/nginx-proxy.manifest.j2
```


## HA 구성 테스트 
### kube-ops-view
```sh
helm repo add geek-cookbook https://geek-cookbook.github.io/charts/

# widnows
helm install kube-ops-view geek-cookbook/kube-ops-view --version 1.2.2 \
  --set service.main.type=NodePort,service.main.ports.http.nodePort=30000 \
  --set env.TZ="Asia/Seoul" --namespace kube-system 

kubectl get deploy,pod,svc,ep -n kube-system -l app.kubernetes.io/instance=kube-ops-view
NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kube-ops-view   1/1     1            1           27s
NAME                                 READY   STATUS    RESTARTS   AGE
pod/kube-ops-view-6658c477d4-g8rl2   1/1     Running   0          27s

open "http://192.168.10.14:30000/#scale=1.5"

# 샘플 앱 배포
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webpod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webpod
  template:
    metadata:
      labels:
        app: webpod
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - sample-app
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: webpod
        image: traefik/whoami
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: webpod
  labels:
    app: webpod
spec:
  selector:
    app: webpod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30003
  type: NodePort
EOF

# 이 경우 워커 노드인 k8s-node4에만 스케쥴링된다.
kubectl get deploy,svc,ep webpod -owide
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES           SELECTOR
deployment.apps/webpod   2/2     2            2           13s   webpod       traefik/whoami   app=webpod

# admin-lb, webpod 응답 확인
while true; do curl -s http://192.168.10.14:30003 | grep Hostname; sleep 1; done

# dns 설정 확인
ssh k8s-node1 cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local
nameserver 10.233.0.3
nameserver 10.0.2.3

# 성공 
ssh k8s-node1 curl -s webpod -I

# 실패
ssh k8s-node1 curl -s webpod.default -I
ssh k8s-node1 curl -s webpod.default.svc.cluster -I

# 성공
ssh k8s-node1 curl -s webpod.default.svc.cluster.local -I
```

### 시나리오 1 : CP-1 종료
```sh
# api-server 주소 확인
cat /root/.kube/config | grep server
    server: https://192.168.10.11:6443

# 터미널 4개 생성
# 터미널 1 : admin-lb
while true; do kubectl get node ; echo ; curl -sk https://192.168.10.11:6443/version | grep gitVersion ; sleep 1; echo ; done

# 터미널 2 : k8s-node2
watch -d kubectl get pod -n kube-system

# 터미널 3 : k8s-node2
kubectl logs -n kube-system nginx-proxy-k8s-node4 -f

# 터미널 4 : k8s-node4
while true; do curl -sk https://127.0.0.1:6443/version | grep gitVersion ; date; sleep 1; echo ; done

# k8s-node1 강제 종료
ssh k8s-node1
poweroff

kubectl logs -n kube-system nginx-proxy-k8s-node4 -f
while true; do curl -sk https://127.0.0.1:6443/version | grep gitVersion ; date; sleep 1; echo ; done
while true; do kubectl get node ; echo ; curl -sk https://192.168.10.12:6443/version | grep gitVersion ; sleep 1; echo ; done

# admin-lb 
# api-server 주소 변경
sed -i 's/192.168.10.11/192.168.10.12/g' /root/.kube/config

# 응답 확인
while true; do kubectl get node ; echo ; curl -sk https://192.168.10.12:6443/version | grep gitVersion ; sleep 1; echo ; done

# 이후 virtaulbox에서 k8s-node1 시작
```

### 시나리오 2 : external LB 활용
```sh
curl -sk https://192.168.10.10:6443/version | grep gitVersion

# api-server 주소 변경
sed -i 's/192.168.10.12/192.168.10.10/g' /root/.kube/config

# 오류 발생
# 왜냐하면 인증서 san list에 192.168.10.10에 대한 정보를 가지고있지 않기 때문이다.
kubectl get node
E0205 15:11:12.725458   15327 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.10.10:6443/api?timeout=32s\": tls: failed to verify certificate: x509: certificate is valid for 10.233.0.1, 192.168.10.12, 192.168.10.11, 127.0.0.1, ::1, 192.168.10.13, 10.0.2.15, fd17:625c:f037:2:a00:27ff:fef8:377b, not 192.168.10.10" 

# SAN 정보 확인
ssh k8s-node1 cat /etc/kubernetes/ssl/apiserver.crt | openssl x509 -text -noout |grep -i dns
                DNS:k8s-node1, DNS:k8s-node2, DNS:k8s-node3, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:lb-apiserver.kubernetes.local, DNS:localhost, IP Address:10.233.0.1, IP Address:192.168.10.11, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1, IP Address:192.168.10.12, IP Address:192.168.10.13, IP Address:10.0.2.15, IP Address:FD17:625C:F037:2:A00:27FF:FEF8:377B

ssh k8s-node1 kubectl get cm -n kube-system kubeadm-config -o yaml
apiServer:
    certSANs:
    - kubernetes
    - kubernetes.default
    - kubernetes.default.svc
    - kubernetes.default.svc.cluster.local
    - 10.233.0.1
    - localhost
    - 127.0.0.1
    - ::1
    - k8s-node1
    - k8s-node2
    - k8s-node3
    - lb-apiserver.kubernetes.local
    - 192.168.10.11
    - 192.168.10.12
    - 192.168.10.13
    - 10.0.2.15
    - fd17:625c:f037:2:a00:27ff:fef8:377b

# admin-lb의 ip와 damain 정보 인증서 SAN 추가
echo "supplementary_addresses_in_ssl_keys: [192.168.10.10, k8s-api-srv.admin-lb.com]" >> inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
supplementary_addresses_in_ssl_keys: [192.168.10.10, k8s-api-srv.admin-lb.com]

# task 조회
ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml --tags "control-plane" --list-tasks

# 새 터미널 생성 후 모니터링
vagrant ssh k8s-node4
while true; do curl -sk https://127.0.0.1:6443/version | grep gitVersion ; date ; sleep 1; echo ; done

# 재배포
ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml --tags "control-plane" --limit kube_control_plane -e kube_version="1.32.9"

# external-lb에서도 api-server에 요청을 잘 보낸다.
kubectl get node -v=6
I0205 15:19:30.150767   16039 round_trippers.go:560] GET https://192.168.10.10:6443/api/v1/nodes?limit=500 200 OK in 21 milliseconds

# 도메인명으로 확인
sed -i 's/192.168.10.10/k8s-api-srv.admin-lb.com/g' /root/.kube/config
I0205 15:20:37.249866   16047 round_trippers.go:560] GET https://k8s-api-srv.admin-lb.com:6443/api/v1/nodes?limit=500 200 OK in 35 milliseconds

# 변경 내역 확인
ssh k8s-node1 cat /etc/kubernetes/ssl/apiserver.crt | openssl x509 -text -noout
...
    DNS:k8s-api-srv.admin-lb.com, IP Address:192.168.10.10

# 하지만 CM에는 적용되지 않는다. 이 경우엔 직접 수정해야 한다.
kubectl get cm -n kube-system kubeadm-config -o yaml |grep -i certsans -A 20

# 수정 
kubectl edit cm -n kube-system kubeadm-config

# CP-1 장애 
cat /root/.kube/config | grep server
    server: https://k8s-api-srv.admin-lb.com:6443

# 새 터미널 2개 생성
# 터미널 1 : admib-lb
while true; do kubectl get node ; echo ; kubectl get pod -n kube-system; sleep 1; echo ; done

# 터미널 1 : k8s-node4
while true; do curl -sk https://127.0.0.1:6443/version | grep gitVersion ; date; sleep 1; echo ; done

vagrant ssh k8s-node1
poweroff

# 당연하게 CP-1이 죽었지만 CP-2, CP-3로 요청이 분산된다. 
# 아후 virtualbox에서 k8s-node1 시작
```

### 시나리오 3 : HA CP 3대 <-> external lb <- 워커 노드
```sh
cat << EOF >> inventory/mycluster/group_vars/all/all.yml
apiserver_loadbalancer_domain_name: "k8s-api-srv.admin-lb.com"
loadbalancer_apiserver:
  address: 192.168.10.10
  port: 6443

# Client-Side LB 미사용, 즉 kubelet/kube-proxy 도 External LB(HAProxy) 단일 사용
loadbalancer_apiserver_localhost: false 
EOF

# 설정 조회
grep "^[^#]" inventory/mycluster/group_vars/all/all.yml

echo "supplementary_addresses_in_ssl_keys: [192.168.10.10, k8s-api-srv.admin-lb.com]" >> inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# 재배포
ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml -e kube_version="1.32.9" 

# 설정값이 적용안된 경우
# ansible-playbook \
#   -i inventory/mycluster/inventory.ini \
#   -v cluster.yml \
#   -e kube_version="1.32.9" \
#   -e apiserver_loadbalancer_domain_name="k8s-api-srv.admin-lb.com" \
#   -e 'loadbalancer_apiserver={"address":"192.168.10.10","port":6443}'

# external-lb 동작 확인
curl -sk https:/192.168.10.10:6443/version
curl -sk https://k8s-api-srv.admin-lb.com:6443/version

# 
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i kubectl cluster-info -v=6; echo; done
I0205 15:43:53.998937   89374 loader.go:402] Config loaded from file:  /root/.kube/config
I0205 16:17:43.485125  101949 round_trippers.go:560] GET https://k8s-api-srv.admin-lb.com:6443/apis?timeout=32s 200 OK in 7 milliseconds

mkdir /root/.kube
scp k8s-node1:/root/.kube/config /root/.kube/
cat /root/.kube/config | grep server
    server: https://k8s-api-srv.admin-lb.com:6443

kubectl get node -owide -v=6
I0205 15:49:04.434651   17581 loader.go:402] Config loaded from file:  /root/.kube/config
GET https://k8s-api-srv.admin-lb.com:6443/api/v1/nodes?limit=500 200 OK in 61 milliseconds

# nginx-proxy 파드 조회
ssh k8s-node4 crictl ps |grep -i nginx
10b97b3e8bab7       c318e336065b1       5 hours ago         Running             nginx-proxy         0                   ee4993d84a921       nginx-proxy-k8s-node4             kube-system

# nginx 파드가 살아있는 경우 강제 삭제
# ssh k8s-node4 rm /etc/kubernetes/manifests/nginx-proxy.yml

ssh k8s-node4 cat /etc/kubernetes/kubelet.conf | grep server
    server: https://k8s-api-srv.admin-lb.com:6443

k get cm -n kube-system kube-proxy -o yaml | grep 'kubeconfig.conf:' -A18
        server: https://k8s-api-srv.admin-lb.com:6443

# 이 설정의 경우 kube-proxy, kubelet, api-server 전부 external-dns를 바라본다.
# 단일 장애 포인트 지점으로 장애 발생 시 k8s 전체에 영향이 가는 구조이다.
```

## 노드 관리
### 노드 증설
```sh
cat scale.yml
- name: Scale the cluster
  ansible.builtin.import_playbook: playbooks/scale.yml

cat playbooks/scale.yml

# 노드 추가
cat << EOF > /root/kubespray/inventory/mycluster/inventory.ini
[kube_control_plane]
k8s-node1 ansible_host=192.168.10.11 ip=192.168.10.11 etcd_member_name=etcd1
k8s-node2 ansible_host=192.168.10.12 ip=192.168.10.12 etcd_member_name=etcd2
k8s-node3 ansible_host=192.168.10.13 ip=192.168.10.13 etcd_member_name=etcd3

[etcd:children]
kube_control_plane

[kube_node]
k8s-node4 ansible_host=192.168.10.14 ip=192.168.10.14
k8s-node5 ansible_host=192.168.10.15 ip=192.168.10.15
EOF

ansible-inventory -i /root/kubespray/inventory/mycluster/inventory.ini --graph
@all:
  |--@ungrouped:
  |--@etcd:
  |  |--@kube_control_plane:
  |  |  |--k8s-node1
  |  |  |--k8s-node2
  |  |  |--k8s-node3
  |--@kube_node:
  |  |--k8s-node4
  |  |--k8s-node5

# ping 확인
ansible -i inventory/mycluster/inventory.ini k8s-node5 -m ping
k8s-node5 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.12"
    },
    "changed": false,
    "ping": "pong"
}

# scale tastk 조회
ansible-playbook -i inventory/mycluster/inventory.ini -v scale.yml --list-tasks

# 워커 노드 추가
ANSIBLE_FORCE_COLOR=true ansible-playbook -i inventory/mycluster/inventory.ini -v scale.yml --limit=k8s-node5 -e kube_version="1.32.9" | tee kubespray_add_worker_node.log

# 워커노드 상태 확인
kubectl get node -owide
k8s-node5   Ready    <none>          81s    v1.32.9   192.168.10.15   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.x86_64   containerd://2.1.5

kubectl get pod -n kube-system -owide |grep k8s-node5
kube-flannel-24ptq                  1/1     Running   1 (61s ago)     89s     192.168.10.15   k8s-node5   <none>           <none>
kube-proxy-nw5r4                    1/1     Running   0               89s     192.168.10.15   k8s-node5   <none>           <none>

ssh k8s-node5 tree /etc/kubernetes
/etc/kubernetes
├── kubeadm-client.conf
├── kubelet.conf
├── kubelet.conf.15517.2026-02-05@17:22:42~
├── kubelet-config.yaml
├── kubelet.env
├── manifests
├── pki -> /etc/kubernetes/ssl
└── ssl
    └── ca.crt

ssh k8s-node5 tree /var/lib/kubelet
/var/lib/kubelet
├── checkpoints
├── config.yaml
├── cpu_manager_state
├── device-plugins
│   └── kubelet.sock
├── kubeadm-flags.env
├── memory_manager_state
├── pki
│   ├── kubelet-client-2026-02-05-17-22-39.pem
│   ├── kubelet-client-current.pem -> /var/lib/kubelet/pki/kubelet-client-2026-02-05-17-22-39.pem
│   ├── kubelet.crt
│   └── kubelet.key
├── plugins
├── plugins_registry
├── pod-resources
│   └── kubelet.sock
└── pods
    ├── 7b66e6c3-2374-406a-aa6d-1c4c7ea43571
    └── ee913188-d27e-453b-b030-e93889566578

ssh k8s-node5 pstree -a

# 기존에 배포한 파드 재분배 
kubectl get pod -owide
kubectl scale deployment webpod --replicas 1
kubectl scale deployment webpod --replicas 2

kubectl get pod -owide
NAME                      READY   STATUS    RESTARTS   AGE    IP            NODE        NOMINATED NODE   READINESS GATES
webpod-697b545f57-2lx96   1/1     Running   0          161m   10.233.67.5   k8s-node4   <none>           <none>
webpod-697b545f57-q697z   1/1     Running   0          11s    10.233.68.2   k8s-node5   <none>           <none>
```

### 노드 삭제
```sh
cat remove-node.yml
- name: Remove node
  ansible.builtin.import_playbook: playbooks/remove_node.yml

cat playbooks/remove_node.yml

kubectl scale deployment webpod --replicas 1
kubectl scale deployment webpod --replicas 2

# pdb 적용
# 동작하지 않는 파드의 최대 개수 0. 즉 모든 파드가 실행중이어야 한다.
cat <<EOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: webpod
  namespace: default
spec:
  maxUnavailable: 0
  selector:
    matchLabels:
      app: webpod
EOF

kubectl get pdb
NAME     MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
webpod   N/A             0                 0                     9s

# 노드 삭제. 그러나 pdb로 인해서 실패한다.
ansible-playbook -i inventory/mycluster/inventory.ini -v remove-node.yml --list-tags
ansible-playbook -i inventory/mycluster/inventory.ini -v remove-node.yml -e node=k8s-node5

kubectl delete pdb webpod

# pdb 삭제 후 재시도
ansible-playbook -i inventory/mycluster/inventory.ini -v remove-node.yml -e node=k8s-node5

# 노드 확인
kubectl get node
k8s-node1   Ready    control-plane   6h19m   v1.32.9
k8s-node2   Ready    control-plane   6h19m   v1.32.9
k8s-node3   Ready    control-plane   6h19m   v1.32.9
k8s-node4   Ready    <none>          6h17m   v1.32.9

# 삭제 확인
# 기존에 배포된 리소스들이 남아잇지 않다.
ssh k8s-node5 tree /etc/kubernetes
/etc/kubernetes  [error opening dir]

ssh k8s-node5 tree /var/lib/kubelet
/var/lib/kubelet  [error opening dir]

ssh k8s-node5 pstree -a

# 노드 재추가
cat << EOF > /root/kubespray/inventory/mycluster/inventory.ini
[kube_control_plane]
k8s-node1 ansible_host=192.168.10.11 ip=192.168.10.11 etcd_member_name=etcd1
k8s-node2 ansible_host=192.168.10.12 ip=192.168.10.12 etcd_member_name=etcd2
k8s-node3 ansible_host=192.168.10.13 ip=192.168.10.13 etcd_member_name=etcd3

[etcd:children]
kube_control_plane

[kube_node]
k8s-node4 ansible_host=192.168.10.14 ip=192.168.10.14
k8s-node5 ansible_host=192.168.10.15 ip=192.168.10.15
EOF

ANSIBLE_FORCE_COLOR=true ansible-playbook -i inventory/mycluster/inventory.ini -v scale.yml --limit=k8s-node5 -e kube_version="1.32.9"

kubectl get node
k8s-node1   Ready    control-plane   6h33m   v1.32.9
k8s-node2   Ready    control-plane   6h32m   v1.32.9
k8s-node3   Ready    control-plane   6h32m   v1.32.9
k8s-node4   Ready    <none>          6h30m   v1.32.9
k8s-node5   Ready    <none>          78s     v1.32.9

# 파드 재분배
kubectl get pod -owide
webpod-697b545f57-2lx96   1/1     Running   0          3h10m   10.233.67.5   k8s-node4   <none>           <none>
webpod-697b545f57-hfj4k   1/1     Running   0          23m     10.233.67.7   k8s-node4   <none>           <none>

kubectl scale deployment webpod --replicas 1
kubectl scale deployment webpod --replicas 2

kubectl get pod -owide
webpod-697b545f57-2lx96   1/1     Running   0          3h11m   10.233.67.5   k8s-node4   <none>           <none>
webpod-697b545f57-q2bn5   1/1     Running   0          33s     10.233.68.2   k8s-node5   <none>           <none>
```

### 비정상 노드 강제 삭제
```sh
# k8s-node5 강제 비정상 상태 만들기
ssh k8s-node5 systemctl stop kubelet
ssh k8s-node5 systemctl stop containerd

k get node |grep node5
k8s-node5   NotReady   <none>          44m   v1.33.7

# unreachable 상태
kc describe node k8s-node5 |grep -i taint -A2
Taints:             node.kubernetes.io/unreachable:NoExecute
                    node.kubernetes.io/unreachable:NoSchedule

# k8s-node5 삭제 시도
# 하지만 실패한다. 왜냐하면 unreachable이기 때문이다. 
ansible-playbook -i inventory/mycluster/inventory.ini -v remove-node.yml -e node=k8s-node5 -e skip_confirmation=true
FAILED - RETRYING: [k8s-node5 -> k8s-node1]: Remove-node | Drain node except daemonsets resource (3 retries left).

# 변수 확인 
cat roles/remove_node/pre_remove/defaults/main.yml
---
allow_ungraceful_removal: false
drain_grace_period: 300
drain_timeout: 360s
drain_retries: 3
drain_retry_delay_seconds: 10

# 노드를 삭제할때 kubectl 명령어를 활용한다. 하지만 이미 kubelet은 응답을 못하는 상황이기에 자연스럽게 노드를 삭제하는 것은 실패하게 된다.
cat roles/remove_node/pre_remove/tasks/main.yml 
- name: Remove-node | Drain node except daemonsets resource
  command: >-
    {{ kubectl }} drain
      --force
      --ignore-daemonsets
      --grace-period {{ drain_grace_period }}
      --timeout {{ drain_timeout }}
      --delete-emptydir-data {{ kube_override_hostname | default(inventory_hostname) }}

cat roles/remove-node/post-remove/tasks/main.yml
  command: "{{ kubectl }} delete node {{ kube_override_hostname | default(inventory_hostname) }}"

# reset_nodes=false : k8s가 가지고 있는 노드의 메타데이터만 삭제한다. kubeadm reset or 서비스 or ssh 수행 X
# allow_ungraceful_removal=true : drain or pod eviction or kubelet 응답 없어도 강행
ansible-playbook -i inventory/mycluster/inventory.ini -v remove-node.yml -e node=k8s-node5 -e reset_nodes=false -e allow_ungraceful_removal=true -e skip_confirmation=true

k get node
NAME        STATUS   ROLES           AGE   VERSION
k8s-node1   Ready    control-plane   23h   v1.33.7
k8s-node2   Ready    control-plane   23h   v1.33.7
k8s-node3   Ready    control-plane   23h   v1.33.7
k8s-node4   Ready    <none>          23h   v1.33.7

# 다시 노드에 편입하기 위해서 배포되었떤 리소스 정리
ssh k8s-node5 systemctl status kubelet --no-pager
ssh k8s-node5 tree /etc/kubernetes

ssh k8s-node5 
kubeadm reset -f
rm -rf /etc/cni/net.d
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet

# iptables 초기화
iptables -t nat -S
iptables -t filter -S
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

systemctl status containerd --no-pager 
systemctl status kubelet --no-pager

systemctl stop kubelet && systemctl disable kubelet
systemctl stop containerd && systemctl disable containerd

# 리소스 정리 확인
tree /etc/cni/net.d
tree /etc/kubernetes
tree /var/lib/kubelet

reboot
# 재시작 후 다시 노드 추가하기 
```

### 클러스터 완전 삭제
클러스트 reset 이후 복구 불가능
```sh
cat reset.yml
- name: Reset the cluster
  ansible.builtin.import_playbook: playbooks/reset.yml

cat playbooks/reset.yml
```

## k8s 버전 업그레이드 
### CNI flannel 버전(0.27.3 -> 0.27.4) upgrade
```sh
# flannel 변수 검색
grep -Rni "flannel_version" inventory/mycluster/ playbooks/ roles/ --include="*.yml" -A2 -B1
roles/kubespray_defaults/defaults/main/download.yml-114-
roles/kubespray_defaults/defaults/main/download.yml:115:flannel_version: 0.27.3
roles/kubespray_defaults/defaults/main/download.yml-116-flannel_cni_version: 1.7.1-flannel1
roles/kubespray_defaults/defaults/main/download.yml-117-cni_version: "{{ (cni_binary_checksums['amd64'] | dict2items)[0].key }}"
--
roles/kubespray_defaults/defaults/main/download.yml-219-flannel_image_repo: "{{ docker_image_repo }}/flannel/flannel"
roles/kubespray_defaults/defaults/main/download.yml:220:flannel_image_tag: "v{{ flannel_version }}"
roles/kubespray_defaults/defaults/main/download.yml-221-flannel_init_image_repo: "{{ docker_image_repo }}/flannel/flannel-cni-plugin"
roles/kubespray_defaults/defaults/main/download.yml-222-flannel_init_image_tag: "v{{ flannel_cni_version }}"

kubectl get ds -n kube-system -owide |grep flannel
kube-flannel              0         0         0       0            0           <none>                   3m24s   kube-flannel   docker.io/flannel/flannel:v0.27.3    app=flannel

ssh k8s-node1 crictl images |grep flannel
docker.io/flannel/flannel-cni-plugin            v1.7.1-flannel1     e5bf9679ea8c3       5.14MB
docker.io/flannel/flannel                       v0.27.3             cadcae92e6360       33.1MB

# flannel 버전 업그레이드 
cat << EOF >> inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml
flannel_version: 0.27.4
EOF

grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml
flannel_interface: enp0s9
flannel_version: 0.27.4

# flannel 버전 업그레이드
# 만일 태그를 통해 특정 작업을 진행하게 되더라도 실패한다. 왜냐하면 CNI 자체가 모든 노드에 구성이 돼야하기 떄문으로 보인다
ansible-playbook -i inventory/mycluster/inventory.ini -v upgrade-cluster.yml --tags "flannel" --list-tasks
ansible-playbook -i inventory/mycluster/inventory.ini -v upgrade-cluster.yml --tags "flannel" -e kube_version="1.32.9"

# 0.27.3 -> 0.27.4
kubectl get ds -n kube-system -owide
NAME                      DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE     CONTAINERS     IMAGES                               SELECTOR
kube-flannel              0         0         0       0            0           <none>                   5m53s   kube-flannel   docker.io/flannel/flannel:v0.27.4    app=flannel

# 0.27.4가 추가되엇다
ssh k8s-node1 crictl images |grep flannel
docker.io/flannel/flannel-cni-plugin            v1.7.1-flannel1     e5bf9679ea8c3       5.14MB
docker.io/flannel/flannel                       v0.27.3             cadcae92e6360       33.1MB
docker.io/flannel/flannel                       v0.27.4             7a52f3ae4ee60       33.2MB

kubectl get pod -n kube-system -l app=flannel -owide
NAME                          READY   STATUS    RESTARTS   AGE    IP              NODE        NOMINATED NODE   READINESS GATES
kube-flannel-ds-arm64-4q9pd   1/1     Running   0          89s    192.168.10.14   k8s-node4   <none>           <none>
kube-flannel-ds-arm64-bm4pq   1/1     Running   0          97s    192.168.10.12   k8s-node2   <none>           <none>
kube-flannel-ds-arm64-d9qxp   1/1     Running   0          81s    192.168.10.13   k8s-node3   <none>           <none>
kube-flannel-ds-arm64-hr6mp   1/1     Running   0          106s   192.168.10.11   k8s-node1   <none>           <none>
```

### 컨트롤 플레인 마이너 버전(1.32.9 -> 1.32.10) 업그레이드[^2]
- Unsafe upgrade
  - cluster.yml 
- Graceful upgrade

> api-server 초 단위 다운타임 발생
```sh
# 모든 노드의 facts 캐시 최신화
ansible-playbook playbooks/facts.yml -b -i inventory/sample/hosts.ini

# k8s version 업그레이드 프로세스 확인
cat upgrade_cluster.yml
- name: Upgrade cluster
  ansible.builtin.import_playbook: playbooks/upgrade_cluster.yml
cat playbooks/upgrade_cluster.yml

# 새 터미널 4개 생성
# 터미널 1 ~ 4 : admin-lb
watch -d kubectl get node
watch -d kubectl get pod -n kube-system -owide
while true; do echo ">> k8s-node1 <<"; ssh k8s-node1 etcdctl.sh endpoint status -w table; echo; echo ">> k8s-node2 <<"; ssh k8s-node2 etcdctl.sh endpoint status -w table; echo ">> k8s-node3 <<"; ssh k8s-node3 etcdctl.sh endpoint status -w table; sleep 1; done
watch -d 'ssh k8s-node1 crictl ps ; echo ; ssh k8s-node1 crictl images'

# 컨트롤 플레인 패치 업그레이드 1.32.9 -> 1.32.10
ANSIBLE_FORCE_COLOR=true ansible-playbook -i inventory/mycluster/inventory.ini -v upgrade-cluster.yml -e kube_version="1.32.10" --limit "kube_control_plane:etcd" | tee kubespray_upgrade.log

# 컨트롤플레인 k8s 버전 확인
k get nodes 
NAME        STATUS   ROLES           AGE   VERSION
k8s-node1   Ready    control-plane   25m   v1.32.10
k8s-node2   Ready    control-plane   25m   v1.32.10
k8s-node3   Ready    control-plane   25m   v1.32.10
k8s-node4   Ready    <none>          25m   v1.32.9
k8s-node5   Ready    <none>          24m   v1.32.9 

ssh k8s-node1 crictl images
IMAGE                                           TAG                 IMAGE ID            SIZE
docker.io/flannel/flannel-cni-plugin            v1.7.1-flannel1     e5bf9679ea8c3       5.14MB
docker.io/flannel/flannel                       v0.27.3             cadcae92e6360       33.1MB
docker.io/flannel/flannel                       v0.27.4             7a52f3ae4ee60       33.2MB
registry.k8s.io/coredns/coredns                 v1.11.3             2f6c962e7b831       16.9MB
registry.k8s.io/kube-apiserver                  v1.32.10            03aec5fd5841e       26.4MB
registry.k8s.io/kube-apiserver                  v1.32.9             02ea53851f07d       26.4MB
registry.k8s.io/kube-controller-manager         v1.32.10            66490a6490dde       24.2MB
registry.k8s.io/kube-controller-manager         v1.32.9             f0bcbad5082c9       24.1MB
registry.k8s.io/kube-proxy                      v1.32.10            8b57c1f8bd2dd       27.6MB
registry.k8s.io/kube-proxy                      v1.32.9             72b57ec14d31e       27.4MB
registry.k8s.io/kube-scheduler                  v1.32.10            fcf368a1abd0b       19.2MB
registry.k8s.io/kube-scheduler                  v1.32.9             1d625baf81b59       19.1MB
registry.k8s.io/metrics-server/metrics-server   v0.8.0              bc6c1e09a843d       20.6MB
registry.k8s.io/pause                           3.10                afb61768ce381       268kB

# etcd 영향 없음 
ssh k8s-node1 systemctl status etcd --no-pager | grep active
     Active: active (running) since Fri 2026-02-06 01:00:44 KST; 27min ago

ssh k8s-node1 etcdctl.sh member list -w table
+------------------+---------+-------+----------------------------+----------------------------+------------+
|        ID        | STATUS  | NAME  |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-------+----------------------------+----------------------------+------------+
|  8b0ca30665374b0 | started | etcd3 | https://192.168.10.13:2380 | https://192.168.10.13:2379 |      false |
| 2106626b12a4099f | started | etcd2 | https://192.168.10.12:2380 | https://192.168.10.12:2379 |      false |
| c6702130d82d740f | started | etcd1 | https://192.168.10.11:2380 | https://192.168.10.11:2379 |      false |
+------------------+---------+-------+----------------------------+----------------------------+------------+

for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i etcdctl.sh endpoint status -w table; echo; done
>> k8s-node1 <<
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | c6702130d82d740f |  3.5.25 |  7.3 MB |      true |      false |         4 |       6717 |               6717 |        |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+

>> k8s-node2 <<
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | 2106626b12a4099f |  3.5.25 |  7.4 MB |     false |      false |         4 |       6719 |               6719 |        |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+

>> k8s-node3 <<
+----------------+-----------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |       ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+-----------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | 8b0ca30665374b0 |  3.5.25 |  7.4 MB |     false |      false |         4 |       6721 |               6721 |        |
+----------------+-----------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+


for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i tree /var/backups; echo; done 
>> k8s-node1 <<
/var/backups
└── etcd-2026-02-06_01:00:41
    ├── member
    │   ├── snap
    │   │   └── db
    │   └── wal
    │       └── 0000000000000000-0000000000000000.wal
    └── snapshot.db

5 directories, 3 files

>> k8s-node2 <<
/var/backups
└── etcd-2026-02-06_01:00:41
    ├── member
    │   ├── snap
    │   │   └── db
    │   └── wal
    │       └── 0000000000000000-0000000000000000.wal
    └── snapshot.db

5 directories, 3 files

>> k8s-node3 <<
/var/backups
└── etcd-2026-02-06_01:00:41
    ├── member
    │   ├── snap
    │   │   └── db
    │   └── wal
    │       └── 0000000000000000-0000000000000000.wal
    └── snapshot.db

5 directories, 3 files
```

### 워커 노드 마이너 버전 업그레이드
```sh
k get pod -A -owide | grep node4
kube-system   coredns-664b99d7c7-r8cz2            1/1     Running   1 (22h ago)   23h   10.233.67.3     k8s-node4   <none>           <none>
kube-system   kube-flannel-ds-arm64-4q9pd         1/1     Running   2 (23m ago)   22h   192.168.10.14   k8s-node4   <none>           <none>
kube-system   kube-proxy-2dclx                    1/1     Running   0             55s   192.168.10.14   k8s-node4   <none>           <none>
kube-system   metrics-server-65fdf69dcb-hjczr     1/1     Running   1 (22h ago)   22h   10.233.67.2     k8s-node4   <none>           <none>
kube-system   nginx-proxy-k8s-node4               1/1     Running   1 (22h ago)   23h   192.168.10.14   k8s-node4   <none>           <none>

k get pod -A -owide | grep node5
kube-system   kube-flannel-ds-arm64-rp5tj         1/1     Running   1 (51s ago)   86s   192.168.10.15   k8s-node5   <none>           <none>
kube-system   kube-proxy-2b9g4                    1/1     Running   0             84s   192.168.10.15   k8s-node5   <none>           <none>
kube-system   nginx-proxy-k8s-node5               1/1     Running   0             85s   192.168.10.15   k8s-node5   <none>           <none>

# 1번에 1대의 노드만만 업그레이드 수행
# ansible-playbook upgrade-cluster.yml -b -i inventory/sample/hosts.ini -e kube_version=1.20.7 -e "serial=1"

# 특정 워커 노드 1대 마이너 버전 업글레이드
ansible-playbook -i inventory/mycluster/inventory.ini -v upgrade-cluster.yml -e kube_version="1.32.10" --limit "k8s-node4"

# node-4에 존재하던 파드가 node-5로 재분배된다.
k get pods -o wide
NAME                      READY   STATUS    RESTARTS   AGE   IP            NODE        NOMINATED NODE   READINESS GATES
webpod-697b545f57-5rdb5   1/1     Running   0          72s   10.233.68.2   k8s-node5   <none>           <none>
webpod-697b545f57-g44h7   1/1     Running   0          4s    10.233.68.3   k8s-node5   <none>           <none>

# node4 마이너 버전 업그레이드 확인 
k get nodes 
NAME        STATUS   ROLES           AGE     VERSION
k8s-node1   Ready    control-plane   23h     v1.32.10
k8s-node2   Ready    control-plane   23h     v1.32.10
k8s-node3   Ready    control-plane   23h     v1.32.10
k8s-node4   Ready    <none>          23h     v1.32.10
k8s-node5   Ready    <none>          8m56s   v1.32.9

# 나머지 노드 작업 수행
ansible-playbook -i inventory/mycluster/inventory.ini -v upgrade-cluster.yml -e kube_version="1.32.10" --limit "k8s-node5"
```

### 컨트롤 플레인 메이저 버전(1.32.10 -> 1.33.7) 업그레이드

```sh
# 새 터미널 4개 생성
# 터미널 1 ~ 4 : admin-lb
watch -d kubectl get node
watch -d kubectl get pod -n kube-system -owide
while true; do echo ">> k8s-node1 <<"; ssh k8s-node1 etcdctl.sh endpoint status -w table; echo; echo ">> k8s-node2 <<"; ssh k8s-node2 etcdctl.sh endpoint status -w table; echo ">> k8s-node3 <<"; ssh k8s-node3 etcdctl.sh endpoint status -w table; sleep 1; done
watch -d 'ssh k8s-node1 crictl ps ; echo ; ssh k8s-node1 crictl images'

# 버전 업그레이드 수행
# kube-proxy 전체 재시작
ANSIBLE_FORCE_COLOR=true ansible-playbook -i inventory/mycluster/inventory.ini -v upgrade-cluster.yml -e kube_version="1.33.7" --limit "kube_control_plane:etcd" | tee kubespray_upgrade-2.log

# 컨트롤 플레인과 워커노드 버전 확인
k get node 
NAME        STATUS   ROLES           AGE   VERSION
k8s-node1   Ready    control-plane   23h   v1.33.7
k8s-node2   Ready    control-plane   23h   v1.33.7
k8s-node3   Ready    control-plane   23h   v1.33.7
k8s-node4   Ready    <none>          23h   v1.32.10
k8s-node5   Ready    <none>          29m   v1.32.10

# kube-proxy 재시작 확인
k get pods -n kube-system |grep proxy
kube-proxy-fslwx                    1/1     Running   0             7m43s
kube-proxy-kp7l5                    1/1     Running   0             7m59s
kube-proxy-s2292                    1/1     Running   0             7m50s
kube-proxy-strj9                    1/1     Running   0             7m44s
kube-proxy-xxxzs                    1/1     Running   0             8m
nginx-proxy-k8s-node4               1/1     Running   1 (22h ago)   23h
nginx-proxy-k8s-node5               1/1     Running   0             29m

# controll-manager, scheduler, kube-proxy, coredns, apiserver 버전 업그레이드 확인
ssh k8s-node1 crictl images
IMAGE                                           TAG                 IMAGE ID            SIZE
docker.io/flannel/flannel-cni-plugin            v1.7.1-flannel1     e5bf9679ea8c3       5.14MB
docker.io/flannel/flannel                       v0.27.3             cadcae92e6360       33.1MB
docker.io/flannel/flannel                       v0.27.4             7a52f3ae4ee60       33.2MB
registry.k8s.io/coredns/coredns                 v1.11.3             2f6c962e7b831       16.9MB
registry.k8s.io/coredns/coredns                 v1.12.0             f72407be9e08c       19.1MB
registry.k8s.io/kube-apiserver                  v1.32.10            03aec5fd5841e       26.4MB
registry.k8s.io/kube-apiserver                  v1.32.9             02ea53851f07d       26.4MB
registry.k8s.io/kube-apiserver                  v1.33.7             6d7bc8e445519       27.4MB
registry.k8s.io/kube-controller-manager         v1.32.10            66490a6490dde       24.2MB
registry.k8s.io/kube-controller-manager         v1.32.9             f0bcbad5082c9       24.1MB
registry.k8s.io/kube-controller-manager         v1.33.7             a94595d0240bc       25.1MB
registry.k8s.io/kube-proxy                      v1.32.10            8b57c1f8bd2dd       27.6MB
registry.k8s.io/kube-proxy                      v1.32.9             72b57ec14d31e       27.4MB
registry.k8s.io/kube-proxy                      v1.33.7             78ccb937011a5       28.3MB
registry.k8s.io/kube-scheduler                  v1.32.10            fcf368a1abd0b       19.2MB
registry.k8s.io/kube-scheduler                  v1.32.9             1d625baf81b59       19.1MB
registry.k8s.io/kube-scheduler                  v1.33.7             94005b6be50f0       19.9MB
registry.k8s.io/metrics-server/metrics-server   v0.8.0              bc6c1e09a843d       20.6MB
registry.k8s.io/pause                           3.10                afb61768ce381       268kB

# etcd는 영향이 없다 왜냐하면 버전 업그레이드가 없기 떄문
ssh k8s-node1 systemctl status etcd --no-pager | grep active
     Active: active (running) since Fri 2026-02-06 23:38:21 KST; 54min ago

ssh k8s-node1 etcdctl.sh member list -w table
+------------------+---------+-------+----------------------------+----------------------------+------------+
|        ID        | STATUS  | NAME  |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-------+----------------------------+----------------------------+------------+
|  8b0ca30665374b0 | started | etcd3 | https://192.168.10.13:2380 | https://192.168.10.13:2379 |      false |
| 2106626b12a4099f | started | etcd2 | https://192.168.10.12:2380 | https://192.168.10.12:2379 |      false |
| c6702130d82d740f | started | etcd1 | https://192.168.10.11:2380 | https://192.168.10.11:2379 |      false |
+------------------+---------+-------+----------------------------+----------------------------+------------+

for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i etcdctl.sh endpoint status -w table; echo; done
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i tree /var/backups; echo; done
>> k8s-node3 <<
/var/backups
└── etcd-2026-02-06_01:00:41
    ├── member
    │   ├── snap
    │   │   └── db
    │   └── wal
    │       └── 0000000000000000-0000000000000000.wal
    └── snapshot.db

5 directories, 3 files
...
```

### 워커 노드 메이저 버전 업그레이드
```sh
kubectl get pod -A -owide | grep node4
default       webpod-697b545f57-4qnlr             1/1     Running   0             22m     10.233.67.7     k8s-node4   <none>           <none>
default       webpod-697b545f57-fd7s9             1/1     Running   0             22m     10.233.67.5     k8s-node4   <none>           <none>
kube-system   coredns-5d784884df-lnk2r            1/1     Running   0             8m9s    10.233.67.9     k8s-node4   <none>           <none>
kube-system   kube-flannel-ds-arm64-4q9pd         1/1     Running   2 (55m ago)   23h     192.168.10.14   k8s-node4   <none>           <none>
kube-system   kube-proxy-kp7l5                    1/1     Running   0             10m     192.168.10.14   k8s-node4   <none>           <none>
kube-system   metrics-server-65fdf69dcb-z9h7w     1/1     Running   0             22m     10.233.67.6     k8s-node4   <none>           <none>
kube-system   nginx-proxy-k8s-node4               1/1     Running   1 (23h ago)   23h     192.168.10.14   k8s-node4   <none>     

kubectl get pod -A -owide | grep node5
kube-system   coredns-5d784884df-7mp58            1/1     Running   0             10m     10.233.68.8     k8s-node5   <none>           <none>
kube-system   kube-flannel-ds-arm64-rp5tj         1/1     Running   1 (32m ago)   33m     192.168.10.15   k8s-node5   <none>           <none>
kube-system   kube-proxy-s2292                    1/1     Running   0             11m     192.168.10.15   k8s-node5   <none>           <none>
kube-system   nginx-proxy-k8s-node5               1/1     Running   0             33m     192.168.10.15   k8s-node5   <none>   

# 워커노드 배포
# 마찬가지로 kube-proxy 전체 재시작
ansible-playbook -i inventory/mycluster/inventory.ini -v upgrade-cluster.yml -e kube_version="1.33.7" --limit "kube_node"

# 버전 확인
k get node
NAME        STATUS   ROLES           AGE   VERSION
k8s-node1   Ready    control-plane   23h   v1.33.7
k8s-node2   Ready    control-plane   23h   v1.33.7
k8s-node3   Ready    control-plane   23h   v1.33.7
k8s-node4   Ready    <none>          23h   v1.33.7
k8s-node5   Ready    <none>          36m   v1.33.7
```

### admin kubeconfig 및 kubectl 업데이트 
```sh
# kubectl 버전 확인
for i in {1..3}; do echo ">> k8s-node$i <<"; ssh k8s-node$i kubectl version; echo; done
>> k8s-node3 <<
Client Version: v1.33.7
Kustomize Version: v5.6.0
Server Version: v1.33.7

# kubectl 버전 확인 
k version
Client Version: v1.32.11
Kustomize Version: v5.5.0
Server Version: v1.33.7

# kubectl 업데이트
cat << EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=kubectl
EOF

dnf install -y -q kubectl --disableexcludes=kubernetes
Upgraded:
  kubectl-1.33.7-150500.1.1.aarch64 

# kubectl 버전 확인
k version
Client Version: v1.33.7
Kustomize Version: v5.6.0
Server Version: v1.33.7

# kubeconfig 업데이트
scp k8s-node1:/root/.kube/config /root/.kube/
cat /root/.kube/config | grep server
sed -i 's/127.0.0.1/192.168.10.10/g' /root/.kube/config
```

[^1]: https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence
[^2]: https://github.com/kubernetes-sigs/kubespray/blob/master/docs/operations/upgrades.md
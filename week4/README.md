### kubespray 전체 설정 정리
```sh
## k8s
# containerd 기본 limit 해제
cat << EOF >> inventory/mycluster/group_vars/all/containerd.yml
containerd_default_base_runtime_spec_patch:
  process:
    rlimits: []
EOF

# cilium cni 사용하기 위한 사전 작업
sed -i 's|^kube_network_plugin:.*$|kube_network_plugin: cni|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|^kube_owner:.*$|kube_owner: root|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# kube_proxy ipvs -> ipatbles, nodelocaldns 비활성화, 인증서 자동 갱신 활성화, 인증서 갱신 systemd 활성화
sed -i 's|kube_proxy_mode: ipvs|kube_proxy_mode: iptables|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|enable_nodelocaldns: true|enable_nodelocaldns: false|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|auto_renew_certificates: false|auto_renew_certificates: true|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|# auto_renew_certificates_systemd_calendar|auto_renew_certificates_systemd_calendar|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

## control plane
# etcd metrics port 설정
echo "etcd_metrics_port: 2381" >> inventory/mycluster/group_vars/all/etcd.yml 

# kube-proxy metrics ip 설정
echo "kube_proxy_metrics_bind_address: 0.0.0.0:10249" >> inventory/mycluster/group_vars/k8s_cluster/kube_control_plane.yml

## Apps
# helm, metrics-server, node-feature, argoocd 활성화
sed -i 's|argocd_enabled: false|argocd_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's/# argocd_namespace: argocd/argocd_namespace: argocd/' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's/# argocd_admin_password: "password"/argocd_admin_password: "password"/' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's|helm_enabled: false|helm_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's|metrics_server_enabled: false|metrics_server_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's|node_feature_discovery_enabled: false|node_feature_discovery_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml

# 전체 변경내역 확인
grep -iE 'kube_owner:|kube_network_plugin:|kube_proxy_mode|enable_nodelocaldns:|^auto_renew_certificates' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
grep -iE 'argocd_enabled:|argocd_namespace:|argocd_admin_password:' inventory/mycluster/group_vars/k8s_cluster/addons.yml
grep -iE 'helm_enabled:|metrics_server_enabled:|node_feature_discovery_enabled:' inventory/mycluster/group_vars/k8s_cluster/addons.yml

# 설정 배포
ANSIBLE_FORCE_COLOR=true ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml -e kube_version="1.33.3" | tee kubespray_install.log

# cilium 설치
helm repo add cilium https://helm.cilium.io/
helm repo update
helm upgrade --install cilium cilium/cilium --version 1.18.6 \
  --namespace kube-system \
  --set operator.replicas=1

k get pods -n kube-system
cilium-envoy-fqm4q                1/1     Running   0          8m46s
cilium-operator-878574d7-2gh84    1/1     Running   0          2m27s
cilium-p2vdc                      1/1     Running   0          8m46s
...

# argocd nodeport 전환
k patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
k get svc -n argocd | grep argocd-server
argocd-server                             NodePort    10.233.51.44    <none>        80:31814/TCP,443:32437/TCP   5m54s

open https://192.168.10.10:32437

```

### 1. VM 환경 설정 및 확인
```sh
vagrant up
vagrant status
vagrant ssh k8s-ctr
vagrant destroy -f && rm -rf .vagrant/

# 커널 버전 확인 
uname -r
6.12.0-55.39.1.el10_0.x86_64

# 파이썬 버전 확인
which python && python -V
/usr/bin/python
Python 3.12.9

dnf install -y python3-pip git

# 네트워크 설정 확인 
ip -br -c -4 addr
lo               UNKNOWN        127.0.0.1/8 
enp0s3           UP             10.0.2.15/24
enp0s8           UP             192.168.10.10/24

# hosts 파일 확인
cat /etc/hosts
192.168.10.10 k8s-ctr

# 서버이름으로 통신 확인
ping -c 1 k8s-ctr
64 bytes from k8s-ctr (192.168.10.10): icmp_seq=1 ttl=64 time=0.024 ms

# ansible 사용하기 위한 ssh password 접속 및 root 접근 활성화
echo "root:qwe123" | chpasswd

cat << EOF >> /etc/ssh/sshd_config
PermitRootLogin yes
PasswordAuthentication yes
EOF

systemctl restart sshd

# 공개키 생성
ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
ls -l ~/.ssh
-rw-------. 1 root root 2602 Jan 26 10:17 id_rsa
-rw-r--r--. 1 root root  566 Jan 26 10:17 id_rsa.pub

# ssh 키 복사
ssh-copy-id -o StrictHostKeyChecking=no root@192.168.10.10

# ssh키 접근 확인
ssh -o StrictHostKeyChecking=no root@k8s-ctr hostname
k8s-ctr

git clone -b v2.29.1 https://github.com/kubernetes-sigs/kubespray.git /root/kubespray
cd kubespray

# 가상환경
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# argocd password에서 에러 발생 시 
pip install passlib

# 앤써블 버전 확인
ansible --version
ansible [core 2.17.14]
  config file = /root/kubespray/ansible.cfg
  configured module search path = ['/root/kubespray/library']
  ansible python module location = /root/kubespray/venv/lib64/python3.12/site-packages/ansible
  ansible collection location = /root/.ansible/collections:/usr/share/ansible/collections
  executable location = /root/kubespray/venv/bin/ansible
  python version = 3.12.9
  jinja version = 3.1.6
  libyaml = True

# 앤서블 설정 확인
cat ansible.cfg

# kubespray 플레이북 확인
tree -L 2

# 플레이북 확인
ls *.yml
cluster.yml  galaxy.yml                 remove-node.yml  reset.yml  upgrade-cluster.yml
_config.yml  recover-control-plane.yml  remove_node.yml  scale.yml  upgrade_cluster.yml

# kubespray가 지원하는 k8s 버전 및 checksum 확인
cat roles/kubespray_defaults/vars/main/checksums.yml | grep -i kube -A40

# 인벤토리 생성
cp -rfp inventory/sample inventory/mycluster

# 주석처리되지 않은 전체 변수 조회
grep "^[^#]" inventory/mycluster/group_vars/all/all.yml
bin_dir: /usr/local/bin
loadbalancer_apiserver_port: 6443
loadbalancer_apiserver_healthcheck_port: 8081
no_proxy_exclude_workers: false
kube_webhook_token_auth: false
kube_webhook_token_auth_url_skip_tls_verify: false
ntp_enabled: false
ntp_manage_config: false
ntp_servers:
  - "0.pool.ntp.org iburst"
  - "1.pool.ntp.org iburst"
  - "2.pool.ntp.org iburst"
  - "3.pool.ntp.org iburst"
unsafe_show_logs: false
allow_unsupported_distribution_setup: false

# 주석처리되지 않은 k8s 변수 조회
grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
kube_config_dir: /etc/kubernetes
local_release_dir: "/tmp/releases"
...

# 환경변수 설정 확인
tree inventory/mycluster/
inventory/mycluster/
├── group_vars
│   ├── all
│   │   ├── all.yml
...
│   └── k8s_cluster
│       ├── addons.yml
│       ├── k8s-cluster.yml
│       ├── k8s-net-calico.yml
│       ├── k8s-net-cilium.yml
...
└── inventory.ini

# kubespray이 어떤 설정을 변경하는지 비교하기 위해 배포 이전에 기존 설정 저장
ip addr | tee -a ip_addr-1.txt 
ss -tnlp | tee -a ss-1.txt
df -hT | tee -a df-1.txt
findmnt | tee -a findmnt-1.txt
sysctl -a | tee -a sysctl-1.txt

# 인벤토리 작성
cat << EOF > /root/kubespray/inventory/mycluster/inventory.ini
k8s-ctr ansible_host=192.168.10.10 ip=192.168.10.10

[kube_control_plane]
k8s-ctr

[etcd:children]
kube_control_plane

[kube_node]
k8s-ctr
EOF

## k8s 설정 변경 및 확인
cat inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml 

# controplane 설정 확인
cat inventory/mycluster/group_vars/k8s_cluster/kube_control_plane.yml 

# etcd 설정 확인, syetemd 관리
grep "^[^#]" inventory/mycluster/group_vars/all/etcd.yml
etcd_data_dir: /var/lib/etcd
etcd_deployment_type: host

# containerd 설정 확인
cat inventory/mycluster/group_vars/all/containerd.yml

# apps 설정 확인
grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/addons.yml

# kube_proxy ipvs -> ipatbles, nodelocaldns 비활성화, 인증서 자동 갱신 활성화, 인증서 갱신 systemd 활성화
sed -i 's|kube_proxy_mode: ipvs|kube_proxy_mode: iptables|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|enable_nodelocaldns: true|enable_nodelocaldns: false|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|auto_renew_certificates: false|auto_renew_certificates: true|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|# auto_renew_certificates_systemd_calendar|auto_renew_certificates_systemd_calendar|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
grep -iE 'kube_network_plugin:|kube_proxy_mode|enable_nodelocaldns:|^auto_renew_certificates' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

## cni
# (생략 가능) 앞서 cilium을 사용하기 위해 cni로 변경했다면
# calico -> flannel, 네트워크 인터페이스 설정
# cat inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml
# sed -i 's|kube_network_plugin: calico|kube_network_plugin: flannel|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
# echo "flannel_interface: enp0s9" >> inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml
# grep "^[^#]" inventory/mycluster/group_vars/k8s_cluster/k8s-net-flannel.yml

## Apps 설정 변경 사항 확인
sed -i 's|helm_enabled: false|helm_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's|metrics_server_enabled: false|metrics_server_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's|node_feature_discovery_enabled: false|node_feature_discovery_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
grep -iE 'helm_enabled:|metrics_server_enabled:|node_feature_discovery_enabled:' inventory/mycluster/group_vars/k8s_cluster/addons.yml
helm_enabled: true
metrics_server_enabled: true
node_feature_discovery_enabled: true

# 배포 시에 수행되는 각 태스크 목록 확인
ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml -e kube_version="1.33.3" --list-tasks 
```

### 2. kubespray 배포 진행
```sh
# kubespray를 통해 k8s 클러스터 설치 진행
# ~/kubespray 디렉토리에서 작업 진행, ansible.cfg를 활용하기 위해서
# kube_version 변수를 통해 원하는 k8s 버전을 지정하여 설치 진행
# ANSIBLE_FORCE_COLOR을 통해 컬러 출력 강제 활성화
ANSIBLE_FORCE_COLOR=true ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml -e kube_version="1.33.3" | tee kubespray_install.log

# kubespray가 진행되는동안 출력되는 로그 확인
more kubespray_install.log

# kubeconfig 위치, k8s 버전, os 버전, feature-gate 설정 확인
kubectl get node -v=6 -o wide
I0126 10:45:49.997246   25147 loader.go:402] Config loaded from file:  /root/.kube/config
I0126 10:45:49.998326   25147 envvar.go:172] "Feature gate default state" feature="InformerResourceVersion" enabled=false
I0126 10:45:49.998417   25147 envvar.go:172] "Feature gate default state" feature="InOrderInformers" enabled=true
I0126 10:45:49.998427   25147 envvar.go:172] "Feature gate default state" feature="WatchListClient" enabled=false
I0126 10:45:49.998433   25147 envvar.go:172] "Feature gate default state" feature="ClientsAllowCBOR" enabled=false
I0126 10:45:49.998437   25147 envvar.go:172] "Feature gate default state" feature="ClientsPreferCBOR" enabled=false
I0126 10:45:50.035314   25147 round_trippers.go:632] "Response" verb="GET" url="https://127.0.0.1:6443/api/v1/nodes?limit=500" status="200 OK" milliseconds=22
NAME      STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                   
     KERNEL-VERSION                 CONTAINER-RUNTIME
k8s-ctr   Ready    control-plane   12m   v1.33.3   192.168.10.10   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.x86_64   containerd://2.1.5

# 파드 상태 조회
kubectl get pod -A

# 배포 이후 변경 내역 저장
ip addr | tee -a ip_addr-2.txt 
ss -tnlp | tee -a ss-2.txt
df -hT | tee -a df-2.txt
findmnt | tee -a findmnt-2.txt
sysctl -a | tee -a sysctl-2.txt

# 변경 내역 비교
# ip_addr는 달라진점 X
# ss은 kubelet, kube 관련 서비스가 추가되엇음
# df는 파드 관련 디렉토리가 추가됨
vi -d ip_addr-1.txt ip_addr-2.txt
vi -d findmnt-1.txt findmnt-2.txt
vi -d sysctl-1.txt sysctl-2.txt
vi -d ss-1.txt ss-2.txt
vi -d df-1.txt df-2.txt

# 변경내역 추출
diff --old-line-format='' --new-line-format='%L' --unchanged-line-format='' sysctl-1.txt sysctl-2.txt > result.txt

# kubectl 자동완성 및 alias 설정
cat << 'EOF' >> ~/.bashrc
source /etc/profile.d/bash_completion.sh
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
EOF

source ~/.bashrc
```

### 3. playbook 단계별 진행 분석
```sh
cat kubespray_install.log | grep -E 'PLAY'
PLAY [Check Ansible version] 
PLAY [Inventory setup and validation] 
PLAY [Install bastion ssh config] 
PLAY [Bootstrap hosts for Ansible] 
PLAY [Gather facts] 
PLAY [Prepare for etcd install] 
PLAY [Add worker nodes to the etcd play if needed] 
PLAY [Install etcd] 
PLAY [Install Kubernetes nodes] 
PLAY [Install the control plane] 
PLAY [Invoke kubeadm and install a CNI] 
PLAY RECAP 

# playbook에서 수행된 task 항목 및 개수 확인 
cat kubespray_install.log | grep -E 'TASK' | wc -l
523

# cluster.yml -> playhboos/cluseer.yml을 참조하고 있다.
cat /root/kubespray/cluster.yml
- name: Install Kubernetes
  ansible.builtin.import_playbook: playbooks/cluster.yml

# 1. 플레이븍 내용을 확인하면 앞서 로그에서 읽엇떤 Play 순서대로 작업이 진행되는 것을 알 수 있다.
cat playbooks/cluster.yml

# 2. boilerplate에서 ansibele 버전 확인, 인벤토리 설정 및 검증, bastion ssh config 작업 진행
cat playbooks/boilerplate.yml
- name: Check ansible version
  import_playbook: ansible_version.yml

- name: Inventory setup and validation
  hosts: all
  gather_facts: false
  tags: always
  roles:
    - dynamic_groups
    - validate_inventory

- name: Install bastion ssh config
  hosts: bastion[0]
  gather_facts: false
  environment: "{{ proxy_disable_env }}"
  roles:
    - { role: kubespray_defaults }
    - { role: bastion-ssh-config, tags: ["localhost", "bastion"] }

# 2.1 ansible_version 버전 정의 확인
cat playbooks/ansible_version.yml
- name: Check Ansible version
  hosts: all
  gather_facts: false
  become: false
  run_once: true
  vars:
    minimal_ansible_version: 2.17.3
    maximal_ansible_version: 2.18.0
  tags: always
  tasks:
    - name: "Check {{ minimal_ansible_version }} <= Ansible version < {{ maximal_ansible_version }}"        
      assert:
        msg: "Ansible must be between {{ minimal_ansible_version }} and {{ maximal_ansible_version }} exclusive - you have {{ ansible_version.string }}"
        that:
          - ansible_version.string is version(minimal_ansible_version, ">=")
          - ansible_version.string is version(maximal_ansible_version, "<")
      tags:
        - check

    - name: "Check that python netaddr is installed"
      assert:
        msg: "Python netaddr is not present"
        that: "'127.0.0.1' | ansible.utils.ipaddr"
      tags:
        - check

    - name: "Check that jinja is not too old (install via pip)"
      assert:
        msg: "Your Jinja version is too old, install via pip"
        that: "{% set test %}It works{% endset %}{{ test == 'It works' }}"
      tags:

# 2.2 인벤토리 그룹 정의
cat roles/dynamic_groups/tasks/main.yml 
- name: Match needed groups by their old names or definition
  vars:
    group_mappings:
      kube_control_plane:
        - kube-master
      kube_node:
        - kube-node
      calico_rr:
        - calico-rr
      no_floating:
        - no-floating
      k8s_cluster:
        - kube_node
        - kube_control_plane
        - calico_rr
  group_by:
    key: "{{ item.key }}"
  when: group_names | intersect(item.value) | length > 0
  loop: "{{ group_mappings | dict2items }}"

# 2.3 참조 의존성
cat roles/validate_inventory/meta/main.yml
dependencies:
  - role: kubespray_defaults

# 2.3 인벤토리 설정 검증
cat roles/validate_inventory/tasks/main.yml 

# kubespray 최상위 기본 변수 확인
tree roles/kubespray_defaults
roles/kubespray_defaults
├── defaults
│   └── main
│       ├── download.yml
│       └── main.yml
└── vars
    └── main
        ├── checksums.yml
        └── main.yml

# k8s 모든 설정, etcd, api-server, ssl, kubelet등
cat roles/kubespray_defaults/defaults/main/main.yml

# 다운로드 경로 확인
cat roles/kubespray_defaults/defaults/main/download.yml

# kubespray가 적용한 커널 파라미터 적용 값 확인
cat /etc/sysctl.d/99-sysctl.conf
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

# 노드에 배치된 설치 파일들
tree /tmp/releases/
├── cni-plugins-linux-amd64-1.8.0.tgz
├── containerd-2.1.5-linux-amd64.tar.gz
├── containerd-rootless-setuptool.sh
├── containerd-rootless.sh
├── crictl
├── crictl-1.33.0-linux-amd64.tar.gz
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
├── helm-3.18.4
│   ├── helm-3.18.4-linux-amd64.tar.gz
│   └── linux-amd64
│       ├── helm
│       ├── LICENSE
│       └── README.md
├── images
├── kubeadm-1.33.3-amd64
├── kubectl-1.33.3-amd64
├── kubelet-1.33.3-amd64
├── nerdctl
├── nerdctl-2.1.6-linux-amd64.tar.gz
└── runc-1.3.4.amd64


cat playbooks/internal_facts.yml
tree roles/bootstrap_os/
cat roles/bootstrap_os/meta/main.yml
cat roles/bootstrap_os/defaults/main.yml 
cat roles/bootstrap_os/files/bootstrap.sh
cat roles/bootstrap_os/handlers/main.yml 
cat roles/bootstrap_os/vars/fedora-coreos.yml

cat roles/bootstrap_os/tasks/rocky.yml 
- name: Import Centos boostrap for Rocky Linux
  import_tasks: centos.yml

cat roles/bootstrap_os/tasks/centos.yml 

tree roles/network_facts/
roles/network_facts/
├── meta
│   └── main.yml
└── tasks
    ├── main.yaml
    └── no_proxy.yml

cat roles/network_facts/meta/main.yml 
dependencies:
  - role: kubespray_defaults

cat roles/network_facts/tasks/main.yaml 
cat roles/network_facts/tasks/no_proxy.yml 
```

### 4. 인벤토리 내 전체 환경 변수 확인
```sh
# 바이너리 설치 경로
cat inventory/mycluster/group_vars/all/all.yml | grep 'bin_dir'
bin_dir: /usr/local/bin

# containerd, crt, etcdctl, kubectl, runc등
tree /usr/local/bin/

# Apps 설정
cat inventory/mycluster/group_vars/k8s_cluster/addons.yml | grep helm
helm_enabled: true

helm version
etcdctl version

containerd --version
containerd github.com/containerd/containerd/v2 v2.1.6 c74fd8780002eb26bd5940ae339d690d891221c2

kubeadm version -o yaml
  gitVersion: v1.33.3

# k8s 환경변수
cat inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# kube 사용자 파일 검색
# 기존 설정 kube -> root 변경으로 출력되지 않음
find / -user kube 2>/dev/null

ls -l /opt
drwxr-xr-x. 3 root root  17 Jan 27 15:34 cni
drwx--x--x. 4 root root  28 Jan 26 10:27 containerd

tree -ug /opt/cni
[root     root    ]  /opt/cni
└── [root     root    ]  bin
    ├── [root     root    ]  bandwidth
    ├── [root     root    ]  bridge
    ├── [root     root    ]  dhcp
    ├── [root     root    ]  dummy
    ├── [root     root    ]  firewall
    ├── [root     root    ]  host-device
    ├── [root     root    ]  host-local
    ├── [root     root    ]  ipvlan
    ├── [root     root    ]  LICENSE
    ├── [root     root    ]  loopback
    ├── [root     root    ]  macvlan
    ├── [root     root    ]  portmap
    ├── [root     root    ]  ptp
    ├── [root     root    ]  README.md
    ├── [root     root    ]  sbr
    ├── [root     root    ]  static
    ├── [root     root    ]  tap
    ├── [root     root    ]  tuning
    ├── [root     root    ]  vlan
    └── [root     root    ]  vrf

ls -l /etc | grep cni
drwxr-xr-x. 3 root root     19 Jan 27 15:28 cni

# flannel cni로 설치한 경우
cat /etc/cni/net.d/10-flannel.conflist

tree -ug /etc/cni
[root     root    ]  /etc/cni
└── [root     root    ]  net.d
    ├── [root     root    ]  10-flannel.conflist

# 인증서 자동 갱신 설정 확인
# 타이머 -> 서비스 -> 쉘 호출
systemctl list-timers --all --no-pager |grep certs
Mon 2026-02-02 03:07:19 KST 5 days -                                      - k8s-certs-renew.timer        k8s-certs-renew.service

# 타이머 상태 조회
systemctl status k8s-certs-renew.timer --no-pager
● k8s-certs-renew.timer - Timer to renew K8S control plane certificates
     Loaded: loaded (/etc/systemd/system/k8s-certs-renew.timer; enabled; preset: disabled)
     Active: active (waiting) since Tue 2026-01-27 15:33:36 KST; 26min ago
 Invocation: 8ddf2bc0bf62461c82030caca5651273
    Trigger: Mon 2026-02-02 03:07:19 KST; 5 days left
   Triggers: ● k8s-certs-renew.service

# 타이머 설정 확인
cat /etc/systemd/system/k8s-certs-renew.timer
[Unit]
Description=Timer to renew K8S control plane certificates
[Timer]
OnCalendar=Mon *-*-1,2,3,4,5,6,7 03:00:00
RandomizedDelaySec=10min
FixedRandomDelay=yes
Persistent=yes
[Install]
WantedBy=multi-user.target

# 서비스 상태 확인
systemctl status k8s-certs-renew.service
○ k8s-certs-renew.service - Renew K8S control plane certificates
     Loaded: loaded (/etc/systemd/system/k8s-certs-renew.service; static)
     Active: inactive (dead)
TriggeredBy: ● k8s-certs-renew.timer

# 서비스 설정 확인
cat /etc/systemd/system/k8s-certs-renew.service
[Unit]
Description=Renew K8S control plane certificates
[Service]
Type=oneshot
ExecStart=/usr/local/bin/k8s-certs-renew.sh

# sh 스크립트 내용 확인 
# kubeadm에 의해 인증서 자동 갱신 및 스태틱 파드 갱신
# admin.conf 갱신
cat /usr/local/bin/k8s-certs-renew.sh
```

### ETC
1. 스태틱 파드 확인 및 삭제 후 api-server 동작 여부 확인 
```sh
watch -d crictl ps
crictl pods --namespace kube-system --name 'kube-scheduler-*|kube-controller-manager-*|kube-apiserver-*|etcd-*' -q | xargs crictl rmp -f
ss -tnlp | grep 6443
until printf "" 2>>/dev/null >>/dev/tcp/127.0.0.1/6443; do sleep 1; done
```

2. fatcs 정보 캐시 확인
```sh
tree /tmp
more /tmp/k8s-ctr
```

### 5. ETCD 사전 작업
```sh
# kubespray etcd 진행상황 확인
more kubespray_install.log | grep -A10 'Prepare for etcd'
PLAY [Prepare for etcd install] 
Monday 26 January 2026  10:25:29 +0900 (0:00:01.471)       0:00:25.428 

TASK [adduser : User | Create User Group] 
changed: [k8s-ctr] => {"changed": true, "gid": 988, "name": "kube-cert", "state": "present", "system": true}
Monday 26 January 2026  10:25:29 +0900 (0:00:00.513)       0:00:25.941 

TASK [adduser : User | Create User] 
changed: [k8s-ctr] => {"changed": true, "comment": "Kubernetes user", "create_home": false, "group": 988, "home": "/home/kube", "name": "kube", "shell": "/sbin/nologin", "state": "present", "system": true, "uid": 990}

# kube 사용자 확인
cat /etc/passwd | tail -n 3
vboxadd:x:991:1::/var/run/vboxadd:/bin/false
kube:x:990:988:Kubernetes user:/home/kube:/sbin/nologin
etcd:x:989:987:Etcd user:/home/etcd:/sbin/nologin

# kube-cret 그룹 확인 
cat /etc/group | tail -n 3
vboxdrmipc:x:989:
kube-cert:x:988:
etcd:x:987:

# etcd 사용자로 소유된 파일 검색
find / -user etcd 2>/dev/null
/etc/ssl/etcd
/etc/ssl/etcd/ssl
/etc/ssl/etcd/ssl/admin-k8s-ctr-key.pem
/etc/ssl/etcd/ssl/admin-k8s-ctr.pem
/etc/ssl/etcd/ssl/ca-key.pem
/etc/ssl/etcd/ssl/ca.pem
/etc/ssl/etcd/ssl/member-k8s-ctr-key.pem
/etc/ssl/etcd/ssl/member-k8s-ctr.pem
/etc/ssl/etcd/ssl/node-k8s-ctr-key.pem
/etc/ssl/etcd/ssl/node-k8s-ctr.pem

# 커널 설정 및 OS 관련 사전 설정
cat roles/kubernetes/preinstall/tasks/0080-system-configurations.yml

# sysctl 설정 확인
grep "^[^#]" /etc/sysctl.conf
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

ls -l /etc/sysctl.d/
lrwxrwxrwx. 1 root root  14 May 18  2025 99-sysctl.conf -> ../sysctl.conf
-rw-r--r--. 1 root root 120 Jan 26 10:16 k8s.conf


# 이미 변경된 설정이라 적용하지 않는다.
more kubespray_install.log | grep -A30 'ip forward'
TASK [kubernetes/preinstall : Enable ip forwarding] 
changed: [k8s-ctr] => {"changed": true}
changed: [k8s-ctr] => (item={'name': 'kernel.keys.root_maxbytes', 'value': 25000000}) => {"ansible_loop_var": "item", "changed": true, "item": {"name": "kernel.keys.root_maxbytes", "value": 25000000}}
changed: [k8s-ctr] => (item={'name': 'kernel.keys.root_maxkeys', 'value': 1000000}) => {"ansible_loop_var": "item", "changed": true, "item": {"name": "kernel.keys.root_maxkeys", "value": 1000000}}
changed: [k8s-ctr] => (item={'name': 'kernel.panic', 'value': 10}) => {"ansible_loop_var": "item", "changed": true, "item": {"name": "kernel.panic", "value": 10}}
changed: [k8s-ctr] => (item={'name': 'kernel.panic_on_oops', 'value': 1}) => {"ansible_loop_var": "item", "changed": true, "item": {"name": "kernel.panic_on_oops", "value": 1}}
changed: [k8s-ctr] => (item={'name': 'vm.overcommit_memory', 'value': 1}) => {"ansible_loop_var": "item", "changed": true, "item": {"name": "vm.overcommit_memory", "value": 1}}
changed: [k8s-ctr] => (item={'name': 'vm.panic_on_oom', 'value': 0}) => {"ansible_loop_var": "item", "changed": true, "item": {"name": "vm.panic_on_oom", "value": 0}}


# k8s를 위한 사전 설정 작업 확인
tree roles/kubernetes/preinstall/tasks/
├── 0010-swapoff.yml
├── 0020-set_facts.yml
├── 0040-verify-settings.yml
├── 0050-create_directories.yml
├── 0060-resolvconf.yml
├── 0061-systemd-resolved.yml
├── 0062-networkmanager-unmanaged-devices.yml
├── 0063-networkmanager-dns.yml
├── 0080-system-configurations.yml
├── 0081-ntp-configurations.yml
├── 0100-dhclient-hooks.yml
├── 0110-dhclient-hooks-undo.yml
└── main.yml

# kubespray가 지원하는 OS 배포판 확인. 사실상 모든 os라고 봐도 무방하다.
cat roles/kubernetes/preinstall/defaults/main.yml
supported_os_distributions:
  - 'RedHat'
  - 'CentOS'
  - 'Fedora'
  - 'Ubuntu'
...

# 사전 작업 순차적 진행
cat roles/kubernetes/preinstall/tasks/main.yml

# k8s 디렉토리 설정
cat roles/kubernetes/preinstall/tasks/0050-create_directories.yml

# kubeadm, 네트워크 및 CP 스태틱 파드 재시작
cat roles/kubernetes/preinstall/handlers/main.yml
- name: Preinstall | reload NetworkManager
  service:
    name: NetworkManager.service
    state: restarted
  listen: Preinstall | update resolvconf for networkmanager

systemctl restart NetworkManager.service
journalctl -u NetworkManager.service --no-pager
```


### 6. Cotainer Engine 
```sh
# 컨테이너 런타임 관련 역할 확인, 마찬가지로 모든 컨테이너 런타임을 지원한다고 봐도 무방하다.
tree roles/container-engine/ -L 2
roles/container-engine/
├── containerd
│   ├── defaults
│   ├── handlers
│   ├── meta
│   ├── molecule
│   ├── tasks
│   └── templates
├── containerd-common
│   ├── defaults
│   ├── meta
│   ├── tasks
│   └── vars
├── crictl
│   ├── handlers
│   ├── tasks
│   └── templates
├── cri-dockerd
│   ├── defaults
│   ├── handlers
│   ├── meta
│   ├── molecule
│   ├── tasks
│   └── templates
├── cri-o
│   ├── defaults
│   ├── handlers
│   ├── meta
│   ├── molecule
│   ├── tasks
│   ├── templates
│   └── vars
├── crun
│   └── tasks
├── docker
│   ├── defaults
│   ├── files
│   ├── handlers
│   ├── meta
│   ├── tasks
│   ├── templates
│   └── vars
├── gvisor
│   ├── molecule
│   └── tasks
├── kata-containers
│   ├── defaults
│   ├── molecule
│   ├── tasks
│   └── templates
├── meta
│   └── main.yml
├── molecule
│   ├── files
│   ├── prepare.yml
│   ├── templates
│   ├── test_cri.yml
│   └── test_runtime.yml
├── nerdctl
│   ├── handlers
│   ├── tasks
│   └── templates
├── runc
│   ├── defaults
│   └── tasks
├── skopeo
│   └── tasks
├── validate-container-engine
│   └── tasks
└── youki
    ├── defaults
    ├── molecule
    └── tasks

# OS 확인, OCI 설치 또는 삭제  kubelet 설치 또는 재시작
cat roles/container-engine/validate-container-engine/tasks/main.yml

# runc 
cat roles/container-engine/runc/tasks/main.yml

# containerd
tree roles/container-engine/containerd/
roles/container-engine/containerd/
├── defaults
│   └── main.yml
├── handlers
│   ├── main.yml
│   └── reset.yml
├── meta
│   └── main.yml
├── molecule
│   └── default
│       ├── converge.yml
│       ├── molecule.yml
│       └── verify.yml
├── tasks
│   ├── main.yml
│   └── reset.yml
└── templates
    ├── config.toml.j2
    ├── config-v1.toml.j2
        # 서비스 설정
    ├── containerd.service.j2 
        # 컨테이너D 레지스트리 및 플러그인 설정
    ├── hosts.toml.j2
    └── http-proxy.conf.j2

cat roles/container-engine/containerd/tasks/main.yml

# containerd의 템플릿 설정 비교
cat /etc/systemd/system/containerd.service
cat roles/container-engine/containerd/templates/containerd.service.j2 

cat /etc/containerd/config.toml
cat roles/container-engine/containerd/templates/config.toml.j2 

# 템플릿에 있는 hosts.toml과 config.toml 설정 확인
tree /etc/containerd/
/etc/containerd/
├── certs.d
│   └── docker.io
│       └── hosts.toml
├── config.toml
└── cri-base.json

# containerd의 이미지 호스트 접속 규칙 및 미러링 설정
cat /etc/containerd/certs.d/docker.io/hosts.toml
server = "https://docker.io"
[host."https://registry-1.docker.io"]
  capabilities = ["pull","resolve"]
  skip_verify = false
  override_path = false

# 순차적으로 레지스트리를 질의하므로, 사내 서비스를 이용한다면 사내 서비스를 최상단에 정의한다.
1. host.private-registry.local
2. host."https://private-registry.local"

# oci 스펙 
ctr oci spec | jq
cat /etc/containerd/cri-base.json | jq
```


### 7. 커널 파라미터
커널 전역 한계  
├─ fs.file-max  
├─ file-nr  
└─ inode 캐시  
> sysctl fs.file-max  
> cat /proc/sys/fs/file-nr  
> cat /proc/slabinfo | egrep 'inode_cache|dentry'  

프로세스 한계    
├─ RLIMIT_NOFILE  
├─ systemd LimitNOFILE  
└─ PAM limits.conf  
> ulimit -n (현재 쉘 기준)  
> systemctl show containerd | grep LimitNOFILE  
> cat /etc/security/limits.conf  
> cat /proc/$$/limits (현재 로그인 세션 기준)  

cgroup 한계    
├─ pids.max  
└─ systemd slice 제한  
> cat /sys/fs/cgroup/system.slice/pids.current  
> cat /sys/fs/cgroup/system.slice/pids.max  
> systemctl show system.slice -p TasksMax  
> systemctl show kubelet.service -p TasksMax  

파일시스템  
├─ inode 수  
├─ dentry 캐시  
└─ mount 옵션
> stat -f /  
> cat /proc/sys/fs/dentry-state
> findmnt -o TARGET,OPTIONS

런타임  
├─ kubelet / containerd  
├─ JVM / Nginx  
└─ epoll / socket 사용량  
> ls /proc/$(pidof containerd)/fd | wc -l(현재 사용 FD)      

> ls /proc/$(pidof kubelet)/fd | wc -l(현재 사용 FD)  
> ss -s  
> cat /proc/sys/net/ipv4/ip_local_port_range  
> cat /proc/sys/net/core/somaxconn  

```sh
# 열수 있는 파일 제한 확인
ctr oci spec | jq | grep -i rlimits -A 5
    "rlimits": [
      {
        "type": "RLIMIT_NOFILE",
        "hard": 1024,
        "soft": 1024
      }

cat /etc/containerd/cri-base.json | jq | grep -i rlimits -A 5
    "rlimits": []

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ubuntu
spec:
  containers:
  - name: ubuntu
    image: ubuntu
    command: ["sh", "-c", "sleep infinity"]
    securityContext:
      privileged: true
EOF

kubectl exec -it ubuntu -- sh -c 'ulimit -a'
time(seconds)        unlimited
file(blocks)         unlimited
data(kbytes)         unlimited
stack(kbytes)        8192
coredump(blocks)     unlimited
memory(kbytes)       unlimited
locked memory(kbytes) unlimited
process              unlimited
nofiles              1048576  # 기본 값 65535
vmemory(kbytes)      unlimited
locks                unlimited
rtprio               0

# 커널 파라미터 파일 최대 개수 확인
cat /proc/sys/fs/file-max
9223372036854775807

# 열려 잇는 파일 확인
# 현재 사용량 / 할당 / 최대량
cat /proc/sys/fs/file-nr
1760    0       9223372036854775807

# 프로세스 단위 제한 
grep "^[^#]" /etc/security/limits.conf
cat /etc/security/limits.conf

# 현재 쉘 기준
ulimit -a

ulimit -n
1024

# etcd limits 조회, sof 64535, hard 65535
cat /proc/$(pidof etcd)/limits | grep "Max open files"
Max open files            40000                40000                files

# ubuntu 파드
cat /proc/27723/limits | grep "Max open files"
Max open files            1048576              1048576              files

# kubelet
cat /proc/$(pidof kubelet)/limits | grep open
Max open files            1000000              1000000              files

systemctl show kubelet | grep LimitNOFILE
LimitNOFILE=524288
LimitNOFILESoft=1024

# containerd
cat /proc/$(pidof containerd)/limits | grep open
Max open files            1048576              1048576              files

systemctl show containerd | grep LimitNOFILE
LimitNOFILE=1048576
LimitNOFILESoft=1048576

# 설정 조회
grep "^[^#]" inventory/mycluster/group_vars/all/containerd.yml
cat inventory/mycluster/group_vars/all/containerd.yml

# 기본적으로 설정된 값 화인
cat roles/container-engine/containerd/defaults/main.yml |grep -i rlimit -A 5
containerd_base_runtime_spec_rlimit_nofile: 65535
containerd_default_base_runtime_spec_patch:
  process:
    rlimits:
      - type: RLIMIT_NOFILE
        hard: "{{ containerd_base_runtime_spec_rlimit_nofile }}"
        soft: "{{ containerd_base_runtime_spec_rlimit_nofile }}"

# OCI 기본 limit 해제
cat << EOF >> inventory/mycluster/group_vars/all/containerd.yml
containerd_default_base_runtime_spec_patch:
  process:
    rlimits: []
EOF

grep "^[^#]" inventory/mycluster/group_vars/all/containerd.yml
containerd_default_base_runtime_spec_patch:
  process:
    rlimits: [] 

# case 1: OCI 제한 해제 후 재배포 
ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml --tags "container-engine" --limit k8s-ctr -e kube_version="1.33.3"

# 변경 내역 확인
# limit가 제거되었다.
cat /etc/containerd/cri-base.json | jq | grep rlimits
    "rlimits": [],

# case 2: 수동 설정
cat << EOF > /etc/containerd/cri-base.json
{"ociVersion": "1.2.1", "process": {"user": {"uid": 0, "gid": 0}, "cwd": "/", "capabilities": {"bounding": ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FSETID", "CAP_FOWNER", "CAP_MKNOD", "CAP_NET_RAW", "CAP_SETGID", "CAP_SETUID", "CAP_SETFCAP", "CAP_SETPCAP", "CAP_NET_BIND_SERVICE", "CAP_SYS_CHROOT", "CAP_KILL", "CAP_AUDIT_WRITE"], "effective": ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FSETID", "CAP_FOWNER", "CAP_MKNOD", "CAP_NET_RAW", "CAP_SETGID", "CAP_SETUID", "CAP_SETFCAP", "CAP_SETPCAP", "CAP_NET_BIND_SERVICE", "CAP_SYS_CHROOT", "CAP_KILL", "CAP_AUDIT_WRITE"], "permitted": ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FSETID", "CAP_FOWNER", "CAP_MKNOD", "CAP_NET_RAW", "CAP_SETGID", "CAP_SETUID", "CAP_SETFCAP", "CAP_SETPCAP", "CAP_NET_BIND_SERVICE", "CAP_SYS_CHROOT", "CAP_KILL", "CAP_AUDIT_WRITE"]}, "noNewPrivileges": true}, "root": {"path": "rootfs"}, "mounts": [{"destination": "/proc", "type": "proc", "source": "proc", "options": ["nosuid", "noexec", "nodev"]}, {"destination": "/dev", "type": "tmpfs", "source": "tmpfs", "options": ["nosuid", "strictatime", "mode=755", "size=65536k"]}, {"destination": "/dev/pts", "type": "devpts", "source": "devpts", "options": ["nosuid", "noexec", "newinstance", "ptmxmode=0666", "mode=0620", "gid=5"]}, {"destination": "/dev/shm", "type": "tmpfs", "source": "shm", "options": ["nosuid", "noexec", "nodev", "mode=1777", "size=65536k"]}, {"destination": "/dev/mqueue", "type": "mqueue", "source": "mqueue", "options": ["nosuid", "noexec", "nodev"]}, {"destination": "/sys", "type": "sysfs", "source": "sysfs", "options": ["nosuid", "noexec", "nodev", "ro"]}, {"destination": "/run", "type": "tmpfs", "source": "tmpfs", "options": ["nosuid", "strictatime", "mode=755", "size=65536k"]}], "linux": {"resources": {"devices": [{"allow": false, "access": "rwm"}]}, "cgroupsPath": "/default", "namespaces": [{"type": "pid"}, {"type": "ipc"}, {"type": "uts"}, {"type": "mount"}, {"type": "network"}], "maskedPaths": ["/proc/acpi", "/proc/asound", "/proc/kcore", "/proc/keys", "/proc/latency_stats", "/proc/timer_list", "/proc/timer_stats", "/proc/sched_debug", "/sys/firmware", "/sys/devices/virtual/powercap", "/proc/scsi"], "readonlyPaths": ["/proc/bus", "/proc/fs", "/proc/irq", "/proc/sys", "/proc/sysrq-trigger"]}}
EOF

# 설정 값이 존재하지않는다.
cat /etc/containerd/cri-base.json | jq | grep rlimits
cat /etc/containerd/cri-base.json | jq

systemctl restart containerd.service
systemctl status containerd.service --no-pager

# 재배포
kubectl delete pod ubuntu

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ubuntu
spec:
  containers:
  - name: ubuntu
    image: ubuntu
    command: ["sh", "-c", "sleep infinity"]
    securityContext:
      privileged: true
EOF

kubectl exec -it ubuntu -- sh -c 'ulimit -a'
time(seconds)        unlimited
file(blocks)         unlimited
data(kbytes)         unlimited
stack(kbytes)        8192
coredump(blocks)     unlimited
memory(kbytes)       unlimited
locked memory(kbytes) unlimited
process              unlimited
nofiles              1048576 # 이미 설정된 값으로 기존 값과 동일하다.
vmemory(kbytes)      unlimited
locks                unlimited
rtprio               0
```


### 8. 다운로드 진행
```sh
tree roles/download/
roles/download/
├── meta
│   └── main.yml
├── tasks
│   ├── check_pull_required.yml
│   ├── download_container.yml
│   ├── download_file.yml
│   ├── extract_file.yml
│   ├── main.yml
│   ├── prep_download.yml
│   ├── prep_kubeadm_images.yml
│   └── set_container_facts.yml
└── templates
    └── kubeadm-images.yaml.j2

# kubeadm 이미지 사전 준비 작업
cat roles/download/tasks/prep_kubeadm_images.yml
cat roles/download/templates/kubeadm-images.yaml.j2

# CRI와 직접 통신하는 바이너리 
nerdctl -n k8s.io images
REPOSITORY                                             TAG                IMAGE ID        CREATED        PLATFORM       SIZE       BLOB SIZE
registry.k8s.io/kube-proxy                             v1.33.3            c69929cfba9e    3 hours ago    linux/amd64    101.2MB    31.89MB
registry.k8s.io/pause                                  3.10               ee6521f290b2    3 hours ago    linux/amd64    737.3kB    318kB
<none>                                                 <none>             39d51a8cf650    3 hours ago    linux/amd64    11.05MB    4.874MB
flannel/flannel-cni-plugin                             v1.7.1-flannel1    39d51a8cf650    3 hours ago    linux/amd64    11.05MB    4.874MB
<none>                                                 <none>             478ca1ac04e4    3 hours ago    linux/amd64    93.23MB    33.99MB
flannel/flannel                                        v0.27.3            478ca1ac04e4    3 hours ago    linux/amd64    93.23MB    33.99MBs
...

```

### 9. ETCD
```sh
# etcd 구조
tree ~/kubespray/roles/etcd
/root/kubespray/roles/etcd
├── handlers
│   ├── backup_cleanup.yml
│   ├── backup.yml
│   └── main.yml
├── meta
│   └── main.yml
├── tasks
│   ├── check_certs.yml
│   ├── configure.yml
│   ├── gen_certs_script.yml
│   ├── gen_nodes_certs_script.yml
│   ├── install_docker.yml
│   ├── install_host.yml
│   ├── join_etcd-events_member.yml
│   ├── join_etcd_member.yml
│   ├── main.yml
│   ├── refresh_config.yml
│   └── upd_ca_trust.yml
└── templates
    ├── etcd-docker.service.j2
    ├── etcd.env.j2
    ├── etcd-events-docker.service.j2
    ├── etcd-events.env.j2
    ├── etcd-events-host.service.j2
    ├── etcd-events.j2
    ├── etcd-host.service.j2
    ├── etcd.j2
    ├── make-ssl-etcd.sh.j2
    └── openssl.conf.j2

cat playbooks/cluster.yml |grep -i "etcd" -A 8
- name: Prepare for etcd install
  hosts: k8s_cluster:etcd
  gather_facts: false
  any_errors_fatal: "{{ any_errors_fatal | default(true) }}"
  environment: "{{ proxy_disable_env }}"
  roles:
    - { role: kubespray_defaults }
    - { role: kubernetes/preinstall, tags: preinstall }
    - { role: "container-engine", tags: "container-engine", when: deploy_container_engine }
    - { role: download, tags: download, when: "not skip_downloads" }
- name: Install etcd
  vars:
    etcd_cluster_setup: true
    etcd_events_cluster_setup: "{{ etcd_events_cluster_enabled }}"
  import_playbook: install_etcd.yml

# etcd 설치
cat playbooks/install_etcd.yml

# pod가 아닌 systemd으로 실행중이다.
systemctl status etcd.service --no-pager
● etcd.service - etcd
     Loaded: loaded (/etc/systemd/system/etcd.service; enabled; preset: disabled)
     Active: active (running) since Mon 2026-01-26 10:32:38 KST; 3h 23min ago
 Invocation: 5a75eaf5f77540ed9f7b1eca3b0ddc36
   Main PID: 18253 (etcd)
      Tasks: 12 (limit: 24795)
     Memory: 81.8M (peak: 87.8M)
        CPU: 4min 49.902s
     CGroup: /system.slice/etcd.service
             └─18253 /usr/local/bin/etcd

cat /etc/systemd/system/etcd.service
[Unit]
Description=etcd
After=network.target
[Service]
Type=notify
User=root
EnvironmentFile=/etc/etcd.env
ExecStart=/usr/local/bin/etcd
NotifyAccess=all
Restart=always
RestartSec=10s
LimitNOFILE=40000
[Install]
WantedBy=multi-user.target

# etcd 환경 변수 
cat /etc/etcd.env 

# etcd 설치후에 새롭게 배포시 백업을 자동으로 수행한다
tree /var/backups/
/var/backups/
└── etcd-2026-01-26_10:32:25
    ├── member
    │   ├── snap
    │   │   └── db
    │   └── wal
    │       └── 0000000000000000-0000000000000000.wal
    └── snapshot.db

# etcd 포트 확인
# 2379는 etcd 포트, 2380은 클러스터 통신 포트이다.
ss -tnlp | grep etcd
LISTEN 0      4096   192.168.10.10:2380       0.0.0.0:*    users:(("etcd",pid=18253,fd=6))                  
LISTEN 0      4096   192.168.10.10:2379       0.0.0.0:*    users:(("etcd",pid=18253,fd=7)) 
LISTEN 0      4096   192.168.10.10:2381       0.0.0.0:*    users:(("etcd",pid=18245,fd=14))

# etcd 클러스터 상태 확인
etcdctl.sh member list -w table

# etcd 메트릭 확인
curl 127.0.0.1:2381/metrics

tree /var/lib/etcd/
/var/lib/etcd/
└── member
    ├── snap
    │   └── db
    └── wal
        ├── 0000000000000000-0000000000000000.wal
        └── 0.tmp

# kind에 설치된 etcd 비교, 정적 파드로 실행된다.
cat /etc/kubernetes/manifests/etcd.yaml
    - --advertise-client-urls=https://192.168.10.100:2379
    - --listen-client-urls=https://127.0.0.1:2379,https://192.168.10.100:2379
    - --listen-metrics-urls=http://127.0.0.1:2381
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /etc/kubernetes/pki/etcd
      name: etcd-certs

# etcd 설정
cat inventory/mycluster/group_vars/all/etcd.yml
etcd_data_dir: /var/lib/etcd
etcd_deployment_type: host

# etcctl 스크립트 확인
cat /usr/local/bin/etcdctl.sh
#!/bin/bash
# Ansible managed
# example invocation: etcdctl.sh get --keys-only --from-key ""
etcdctl \
  --cacert /etc/ssl/etcd/ssl/ca.pem \
  --cert /etc/ssl/etcd/ssl/admin-k8s-ctr.pem \
  --key /etc/ssl/etcd/ssl/admin-k8s-ctr-key.pem "$@"

etcdctl.sh -h

etcdctl.sh get --keys-only --from-key ""

etcdctl.sh endpoint status -w table
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | a997582217e26c7f |  3.5.25 |  2.3 MB |      true |      false |         3 |      13096 |              13096 |        |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+

etcdctl.sh member list -w table
+------------------+---------+-------+----------------------------+----------------------------+------------+
|        ID        | STATUS  | NAME  |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-------+----------------------------+----------------------------+------------+
| a997582217e26c7f | started | etcd1 | https://192.168.10.10:2380 | https://192.168.10.10:2379 |      false |
+------------------+---------+-------+----------------------------+----------------------------+------------+

# etcd 인증서 확인
tree /etc/ssl/etcd
/etc/ssl/etcd
├── openssl.conf
└── ssl
    ├── admin-k8s-ctr-key.pem
    ├── admin-k8s-ctr.pem
    ├── ca-key.pem
    ├── ca.pem
    ├── member-k8s-ctr-key.pem
    ├── member-k8s-ctr.pem
    ├── node-k8s-ctr-key.pem
    └── node-k8s-ctr.pem

cat /etc/ssl/etcd/openssl.conf
```

### 10. Node
```sh
# 노드 구조 확인
roles/kubernetes/node
├── defaults
│   └── main.yml
├── handlers
│   └── main.yml
├── tasks
│   ├── facts.yml
│   ├── install.yml
│   ├── kubelet.yml
│   ├── loadbalancer
│   │   ├── haproxy.yml
│   │   ├── kube-vip.yml
│   │   └── nginx-proxy.yml
│   └── main.yml
├── templates
│   ├── http-proxy.conf.j2
│   ├── kubelet-config.v1beta1.yaml.j2
│   ├── kubelet.env.v1beta1.j2
│   ├── kubelet.service.j2
│   ├── loadbalancer
│   │   ├── haproxy.cfg.j2
│   │   └── nginx.conf.j2
│   ├── manifests
│   │   ├── haproxy.manifest.j2
│   │   ├── kube-vip.manifest.j2
│   │   └── nginx-proxy.manifest.j2
│   └── node-kubeconfig.yaml.j2
└── vars
    ├── fedora.yml
    ├── ubuntu-18.yml
    ├── ubuntu-20.yml
    ├── ubuntu-22.yml
    └── ubuntu-24.yml

cat playbooks/cluster.yml |grep -i nodes -A 8
- name: Install Kubernetes nodes
  hosts: k8s_cluster
  gather_facts: false
  any_errors_fatal: "{{ any_errors_fatal | default(true) }}"
  environment: "{{ proxy_disable_env }}"
  roles:
    - { role: kubespray_defaults }
    - { role: kubernetes/node, tags: node }

# kubelet 설치부터 커널 모듈 활성화
cat roles/kubernetes/node/tasks/main.yml
cat roles/kubernetes/node/tasks/kubelet.yml

# 배포 이전 파라미터 조회
cat sysctl-1.txt | grep net.ipv4.ip_local_reserved_ports
net.ipv4.ip_local_reserved_ports =

# 배포 이후 nodePort 파라미터 조회
cat sysctl-2.txt | grep net.ipv4.ip_local_reserved_ports
net.ipv4.ip_local_reserved_ports = 30000-32767

# 커널 파라미터 조회
sysctl net.ipv4.ip_local_reserved_ports
net.ipv4.ip_local_reserved_ports = 30000-32767

# 정적 파드 확인
tree /etc/kubernetes/manifests/

# k8s yaml 및 설정 파일 확인
tree /etc/kubernetes/

# kubelet 서비스 파일 확인
cat /etc/kubernetes/kubelet-config.yaml
cat /etc/systemd/system/kubelet.service

# 노드에 할당할수 있는 파드 최대 개수
kubectl describe node | grep pods
  pods:               110
```

### 11. Control Plane
```sh
# CP 구조 확인
tree roles/kubernetes/control-plane/
roles/kubernetes/control-plane/
├── defaults
│   └── main
│       ├── etcd.yml
│       ├── kube-proxy.yml
│       ├── kube-scheduler.yml
│       └── main.yml
├── handlers
│   └── main.yml
├── meta
│   └── main.yml
├── tasks
│   ├── check-api.yml
│   ├── define-first-kube-control.yml
│   ├── encrypt-at-rest.yml
│   ├── kubeadm-backup.yml
│   ├── kubeadm-etcd.yml
│   ├── kubeadm-fix-apiserver.yml
│   ├── kubeadm-secondary.yml
│   ├── kubeadm-setup.yml
│   ├── kubeadm-upgrade.yml
│   ├── kubelet-fix-client-cert-rotation.yml
│   ├── main.yml
│   └── pre-upgrade.yml
...

# CP 구성 태스크
cat roles/kubernetes/control-plane/tasks/main.yml 

# kubeadm init, upgrade, join 작업
cat roles/kubernetes/control-plane/tasks/kubeadm-setup.yml 

# CP 기본 변수 확인
cat roles/kubernetes/control-plane/defaults/main/main.yml

tree roles/kubernetes/client/
roles/kubernetes/client/
├── defaults
│   └── main.yml
└── tasks
    └── main.yml

# kubeconfig 설정 변수
cat roles/kubernetes/client/defaults/main.yml 
kubeconfig_localhost: false
kubeconfig_localhost_ansible_host: false
kubectl_localhost: false
artifacts_dir: "{{ inventory_dir }}/artifacts"
kube_config_dir: "/etc/kubernetes"
kube_apiserver_port: "6443"

# kbueconfig 설정 및 api-server 엔드포인트 설정
cat roles/kubernetes/client/tasks/main.yml

tree roles/kubernetes-apps/cluster_roles/
roles/kubernetes-apps/cluster_roles/
├── files
│   └── k8s-cluster-critical-pc.yml
├── tasks
│   └── main.yml
└── templates
    ├── namespace.j2
    ├── node-crb.yml.j2
    └── vsphere-rbac.yml.j2

cat roles/kubernetes-apps/cluster_roles/tasks/main.yml

# kubeadm 설정 확인
cat /etc/kubernetes/kubeadm-config.yaml

# 정적 파드
tree /etc/kubernetes/manifests/
/etc/kubernetes/manifests/
├── kube-apiserver.yaml
├── kube-controller-manager.yaml
└── kube-scheduler.yaml

kubectl get pod -n kube-system -l tier=control-plane
kube-apiserver-k8s-ctr            1/1     Running   0          3h50m
kube-controller-manager-k8s-ctr   1/1     Running   1          3h50m
kube-scheduler-k8s-ctr            1/1     Running   1          3h50m

# ipv4 및 ipv6 허용
ss -tnp | grep 'ffff'
ESTAB 0      0          [::ffff:127.0.0.1]:6443  [::ffff:127.0.0.1]:52520 users:(("kube-apiserver",pid=20534,fd=70))
ESTAB 0      0          [::ffff:127.0.0.1]:6443  [::ffff:127.0.0.1]:44646 users:(("kube-apiserver",pid=20534,fd=73))
ESTAB 0      0          [::ffff:127.0.0.1]:6443  [::ffff:127.0.0.1]:52538 users:(("kube-apiserver",pid=20534,fd=68))
ESTAB 0      0          [::ffff:127.0.0.1]:6443  [::ffff:127.0.0.1]:40252 users:(("kube-apiserver",pid=20534,fd=72))
ESTAB 0      0          [::ffff:127.0.0.1]:6443  [::ffff:127.0.0.1]:52554 users:(("kube-apiserver",pid=20534,fd=71))
ESTAB 0      0      [::ffff:192.168.10.10]:6443  [::ffff:10.0.2.15]:26645 users:(("kube-apiserver",pid=20534,fd=69))
ESTAB 0      0          [::ffff:127.0.0.1]:6443  [::ffff:127.0.0.1]:52534 users:(("kube-apiserver",pid=20534,fd=67))

# 정적 파드들의 ip 설정
kubectl describe pod -n kube-system kube-apiserver-k8s-ctr | grep bind-address
      --bind-address=::
kubectl describe pod -n kube-system kube-controller-manager-k8s-ctr |grep bind-address
      --bind-address=::
kubectl describe pod -n kube-system kube-scheduler-k8s-ctr |grep bind-address
      --bind-address=::

# kubeadm 인증서 확인
kubeadm certs check-expiration
[check-expiration] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[check-expiration] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.        
W0126 14:41:39.726697   51164 utils.go:69] The recommended value for "clusterDNS" in "KubeletConfiguration" is: [10.233.0.10]; the provided value is: [10.233.0.3]
CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Jan 26, 2027 01:33 UTC   364d            ca                      no
apiserver                  Jan 26, 2027 01:33 UTC   364d            ca                      no
apiserver-kubelet-client   Jan 26, 2027 01:33 UTC   364d            ca                      no
controller-manager.conf    Jan 26, 2027 01:33 UTC   364d            ca                      no
front-proxy-client         Jan 26, 2027 01:33 UTC   364d            front-proxy-ca          no
scheduler.conf             Jan 26, 2027 01:33 UTC   364d            ca                      no
super-admin.conf           Jan 26, 2027 01:33 UTC   364d            ca                      no
CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Jan 24, 2036 01:33 UTC   9y              no
front-proxy-ca          Jan 24, 2036 01:33 UTC   9y              no

# 인증서 구조 확인
tree /etc/kubernetes/ssl/
/etc/kubernetes/ssl/
├── apiserver.crt
├── apiserver.key
├── apiserver-kubelet-client.crt
├── apiserver-kubelet-client.key
├── ca.crt
├── ca.key
├── front-proxy-ca.crt
├── front-proxy-ca.key
├── front-proxy-client.crt
├── front-proxy-client.key
├── sa.key
└── sa.pub

# k8s CA 인증서 내용 확인
cat /etc/kubernetes/ssl/ca.crt | openssl x509 -text -noout
        Issuer: CN=kubernetes
        Validity
            Not Before: Jan 26 01:28:10 2026 GMT
            Not After : Jan 24 01:33:10 2036 GMT
        Subject: CN=kubernetes
...

cat /etc/kubernetes/ssl/apiserver.crt | openssl x509 -text -noout
        Issuer: CN=kubernetes
        Validity
            Not Before: Jan 26 01:28:10 2026 GMT
            Not After : Jan 26 01:33:10 2027 GMT
        Subject: CN=kube-apiserver
        X509v3 Subject Alternative Name:
            DNS:k8s-ctr, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:lb-apiserver.kubernetes.local, DNS:localhost, IP Address:10.233.0.1, IP Address:192.168.10.10, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1, IP Address:10.0.2.15, IP Address:FD17:625C:F037:2:A00:27FF:FEF8:377B
...

cat /etc/kubernetes/ssl/apiserver-kubelet-client.crt | openssl x509 -text -noout
  Issuer: CN=kubernetes
        Validity
            Not Before: Jan 26 01:28:10 2026 GMT
            Not After : Jan 26 01:33:10 2027 GMT
        Subject: O=kubeadm:cluster-admins, CN=kube-apiserver-kubelet-client
...

cat /etc/kubernetes/ssl/front-proxy-ca.crt | openssl x509 -text -noout
        Issuer: CN=front-proxy-ca
        Validity
            Not Before: Jan 26 01:28:10 2026 GMT
            Not After : Jan 24 01:33:10 2036 GMT
        Subject: CN=front-proxy-ca
        X509v3 Subject Alternative Name:
            DNS:front-proxy-ca
...
          
cat /etc/kubernetes/ssl/front-proxy-client.crt | openssl x509 -text -noout
 Issuer: CN=front-proxy-ca
        Validity
            Not Before: Jan 26 01:28:10 2026 GMT
            Not After : Jan 26 01:33:10 2027 GMT
        Subject: CN=front-proxy-client
...
```

### 12. CNI
Helm으로 배포한 상태이라 cilium 설정이 존재하지 않지만 참조 용도
```sh
# cni 종류
tree roles/network_plugin/ -L 1
roles/network_plugin/
├── calico
├── calico_defaults
├── cilium
├── cni
├── custom_cni
├── flannel
├── kube-ovn
├── kube-router
├── macvlan
├── meta
├── multus
└── ovn4nfv

# 기본 cni 
tree roles/network_plugin/cni/
roles/network_plugin/cni/
├── defaults
│   └── main.yml
└── tasks
    └── main.yml

# cilium
roles/network_plugin/cilium/
├── defaults
│   └── main.yml
├── tasks
│   ├── apply.yml
│   ├── check.yml
│   ├── install.yml
│   ├── main.yml
│   ├── remove_old_resources.yml
│   ├── reset_iface.yml
│   └── reset.yml
└── templates
    ├── 000-cilium-portmap.conflist.j2
    ├── cilium
    │   ├── cilium-bgp-advertisement.yml.j2
    │   ├── cilium-bgp-cluster-config.yml.j2
    │   ├── cilium-bgp-node-config-override.yml.j2
    │   ├── cilium-bgp-peer-config.yml.j2
    │   ├── cilium-bgp-peering-policy.yml.j2
    │   └── cilium-loadbalancer-ip-pool.yml.j2
    └── values.yaml.j2

# cni 바이너리 소유자 설정 기본값은 kube이지만 현재 root로 변환한 상태이다
cat roles/network_plugin/cni/defaults/main.yml 
cni_bin_owner: "{{ kube_owner }}"

# cni 기본 경로
cat roles/network_plugin/cni/tasks/main.yml
- name: CNI | make sure /opt/cni/bin exists
  file:
    path: /opt/cni/bin
    state: directory
    mode: "0755"
    owner: "{{ cni_bin_owner }}"
    recurse: true

- name: CNI | Copy cni plugins
  unarchive:
    src: "{{ downloads.cni.dest }}"
    dest: "/opt/cni/bin"
    mode: "0755"
    owner: "{{ cni_bin_owner }}"
    remote_src: true

tree -ug /opt/cni/bin
[root     root    ]  /opt/cni/bin
├── [root     root    ]  bandwidth
├── [root     root    ]  bridge
├── [root     root    ]  cilium-cni
├── [root     root    ]  dhcp
├── [root     root    ]  dummy
├── [root     root    ]  firewall
├── [root     root    ]  host-device
├── [root     root    ]  host-local
├── [root     root    ]  ipvlan
├── [root     root    ]  LICENSE
├── [root     root    ]  loopback
├── [root     root    ]  macvlan
├── [root     root    ]  portmap
├── [root     root    ]  ptp
├── [root     root    ]  README.md
├── [root     root    ]  sbr
├── [root     root    ]  static
├── [root     root    ]  tap
├── [root     root    ]  tuning
├── [root     root    ]  vlan
└── [root     root    ]  vrf

# cilium 태스크 확인
cat roles/network_plugin/cilium/tasks/main.yml 
- name: Cilium check
  import_tasks: check.yml
- name: Cilium install
  include_tasks: install.yml
- name: Cilium remove old resources
  when: cilium_remove_old_resources
  include_tasks: remove_old_resources.yml
- name: Cilium apply
  include_tasks: apply.yml

# ipsec, wireguard와 같은 서비스에 영향을 끼칠수 잇는 요소 검증
cat roles/network_plugin/cilium/tasks/check.yml 

# 설치 및 bpf, etcd, ssl 환경 설정
cat roles/network_plugin/cilium/tasks/install.yml 

# 예전 리소스 삭제
cat roles/network_plugin/cilium/tasks/remove_old_resources.yml 

# 고급 네트워킹 기능 및 CRD 설치
cat roles/network_plugin/cilium/tasks/apply.yml 

# cilium 기본 변수 확인
cat roles/network_plugin/cilium/defaults/main.yml 

# main이 주입하는 설정 템플릿
cat roles/network_plugin/cilium/templates/values.yaml.j2
```

### 13. k8s addons
```sh
# local cis 확인
# local_volume_provisioner, local_path_provisioner
tree roles/kubernetes-apps/external_provisioner/

# k8s 관련 앱 확인
tree roles/kubernetes-apps/ -L 1
roles/kubernetes-apps/
├── cluster_roles
├── helm
├── metrics_server
├── node_feature_discovery
...

k get deployment -n kube-system coredns dns-autoscaler -o wide
coredns          1/1     1            1           6m2s    coredns      registry.k8s.io/coredns/coredns:v1.12.0                      k8s-app=kube-dns
dns-autoscaler   1/1     1            1           5m57s   autoscaler   registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.8.8   k8s-app=dns-autoscaler

# coredns CM 조회
k describe cm -n kube-system coredns
Corefile:
----
.:53 {
    errors {
    }
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
      pods insecure
      fallthrough in-addr.arpa ip6.arpa
    }
    prometheus :9153
    forward . /etc/resolv.conf {
      prefer_udp
      max_concurrent 1000
    }
    cache 30

    loop
    reload
    loadbalance
}


k describe cm -n kube-system dns-autoscaler
{"coresPerReplica":256,"min":1,"nodesPerReplica":16,"preventSinglePointFailure":false}

tree /etc/kubernetes/addons/
/etc/kubernetes/addons/
├── metrics_server
│   ├── auth-delegator.yaml
│   ├── auth-reader.yaml
│   ├── metrics-apiservice.yaml
│   ├── metrics-server-deployment.yaml
│   ├── metrics-server-sa.yaml
│   ├── metrics-server-service.yaml
│   ├── resource-reader-clusterrolebinding.yaml
│   └── resource-reader.yaml
└── node_feature_discovery
    ├── nfd-api-crds.yaml
    ├── nfd-clusterrolebinding.yaml
    ├── nfd-clusterrole.yaml
    ├── nfd-gc.yaml
    ├── nfd-master-conf.yaml
    ├── nfd-master.yaml
    ├── nfd-ns.yaml
    ├── nfd-rolebinding.yaml
    ├── nfd-role.yaml
    ├── nfd-serviceaccount.yaml
    ├── nfd-service.yaml
    ├── nfd-topologyupdater-conf.yaml
    ├── nfd-worker-conf.yaml
    └── nfd-worker.yaml

k get pod -n kube-system -l app.kubernetes.io/name=metrics-server
metrics-server-7cd7f9897-kfhcv   1/1     Running   1 (72s ago)   2m48s

k top pod -A
NAMESPACE     NAME                                             CPU(cores)   MEMORY(bytes)   
kube-system   cilium-envoy-fqm4q                                  2m           20Mi
kube-system   cilium-operator-878574d7-2gh84                      2m           51Mi
kube-system   cilium-p2vdc                                        17m          278Mi
kube-system   coredns-5d784884df-snz2d                            1m           53Mi
kube-system   dns-autoscaler-676999957f-f774k                     1m           31Mi
kube-system   kube-apiserver-k8s-ctr                              29m          339Mi
kube-system   kube-controller-manager-k8s-ctr                     10m          74Mi
kube-system   kube-proxy-jvw68                                    1m           22Mi
kube-system   kube-scheduler-k8s-ctr                              4m           28Mi
kube-system   metrics-server-7cd7f9897-bn7vd                      4m           48Mi
```

이후 내용은 맨 앞에 정의한 설정과 동일한 설정으로 task들의 진행 내용과 설정 진행 과정을 설명한 과정으로 스킵해도 된다.

### 14. argocd
kubespray로 argocd 배포하기, [tag list](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ansible/ansible.md)에서 apps 태그로 배포 가능하다.

```sh
# k8s app 설치 플레이북 확인
cat playbook/cluster.yml
- name: Install Kubernetes apps
  hosts: kube_control_plane
  gather_facts: false
  any_errors_fatal: "{{ any_errors_fatal | default(true) }}"
  environment: "{{ proxy_disable_env }}"
  roles:
    - { role: kubespray_defaults }
    - { role: kubernetes-apps/external_cloud_controller, tags: external-cloud-controller }
    - { role: kubernetes-apps/policy_controller, tags: policy-controller }
    - { role: kubernetes-apps/ingress_controller, tags: ingress-controller }
    - { role: kubernetes-apps/external_provisioner, tags: external-provisioner }
    # agrocd가 배포되는 태그 부분
    - { role: kubernetes-apps, tags: apps }

# 그룹변수 설정 확인 
cat inventory/mycluster/group_vars/k8s_cluster/addons.yml |grep -i argocd -A 5
argocd_enabled: false
# argocd_namespace: argocd
# argocd_namespace: "password"

# argo enabled 및 argocd_namespace, argocd_admin_password 설정 및 확인
sed -i 's|argocd_enabled: false|argocd_enabled: true|g' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's/# argocd_namespace: argocd/argocd_namespace: argocd/' inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i 's/# argocd_admin_password: "password"/argocd_admin_password: "password"/' inventory/mycluster/group_vars/k8s_cluster/addons.yml
grep -iE 'argocd_enabled:|argocd_namespace:|argocd_admin_password:' inventory/mycluster/group_vars/k8s_cluster/addons.yml

# argocd role 구조 확인
tree roles/kubernetes-apps/argocd/
├── defaults
    # 기본 변수 확인
    # graoup_vars의 argocd 변수와 동일하다. argocd 버전 정의 포함
│   └── main.yml
├── tasks
│   └── main.yml
└── templates
    # argocd 네임스페이스 템플릿 파일
    └── argocd-namespace.yml.j2 

cat roles/kubernetes-apps/argocd/defaults/main.yml 
cat roles/kubernetes-apps/argocd/tasks/main.yml 
# 1. yq 다운 및 bin 경로 이동
# 2. agro ns 매니페스트 전달
# 3. 외부 argo 매니페스트 다운로드
# 4. argocd k8s 경로 전달
# 5. argocd 배포

ls /etc/kubernetes/ |grep argo
argocd-install.yml
argocd-namespace.yml

# argcdo 배포
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml --tags apps --skip-tags=bootstrap_os,control-plane,etcd,helm,kubeadm,kubelet,kube-controller-manager,kube-proxy,metrics_server

k get pods -n argocd
argocd-application-controller-0                     1/1     Running   0              3m6s
argocd-applicationset-controller-746f9cdd78-nqhsl   1/1     Running   0              3m8s
argocd-dex-server-86b74779cb-rtnt8                  1/1     Running   1 (2m4s ago)   3m8s
argocd-notifications-controller-779d4f9cf5-7l4gk    1/1     Running   0              3m8s
argocd-redis-7d94854547-nxn2q                       1/1     Running   0              3m7s
argocd-repo-server-7f79dc6c97-d9zc7                 1/1     Running   0              3m7s
argocd-server-84fdb46f68-wswfb                      1/1     Running   0              3m6s

k get svc -n argocd

k patch svc argocd-server -n password -p '{"spec": {"type": "NodePort"}}'

k get svc -n argocd | grep argocd-server
argocd-server                             NodePort    10.233.10.164   <none>        80:32381/TCP,443:31232/TCP   10m

open https://192.168.10.10:31232
```

### 15. etcd 메트릭
```sh
tree roles -L 1 |grep etcd
├── etcd
├── etcdctl_etcdutl
├── etcd_defaults

# etcd 설정 찾기
grep -r "etcd_metrics" .

# 기본 변수 설정 확인 
cat roles/etcd_defaults/defaults/main.yml  |grep port
# etcd_metrics_port: 2381

# etcd 환경 설정 파일 확인
cat roles/etcd/templates/etcd.env.j2 |grep -i etcd_metrics -A 5
ETCD_METRICS={{ etcd_metrics }}
{% if etcd_listen_metrics_urls is defined %}
ETCD_LISTEN_METRICS_URLS={{ etcd_listen_metrics_urls }}
{% elif etcd_metrics_port is defined %}
ETCD_LISTEN_METRICS_URLS=http://{{ etcd_address | ansible.utils.ipwrap }}:{{ etcd_metrics_port }},http://127.0.0.1:{{ etcd_metrics_port }}
{% endif %}

# etcd 메트릭 포트 추가
echo "etcd_metrics_port: 2381" >> inventory/mycluster/group_vars/all/etcd.yml 
cat inventory/mycluster/group_vars/all/etcd.yml 

# 배포
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml --tags etcd

# 포트 확인
ss -tnlp | grep 2381
LISTEN 0      4096   192.168.10.10:2381       0.0.0.0:*    users:(("etcd",pid=101408,fd=14))                
LISTEN 0      4096       127.0.0.1:2381       0.0.0.0:*    users:(("etcd",pid=101408,fd=13))                

# 메트릭 정보 조회
curl 192.168.10.10:2381/metrics

# etcd 설정 확인
cat /etc/etcd.env |grep -i metrics
ETCD_METRICS=basic
ETCD_LISTEN_METRICS_URLS=http://192.168.10.10:2381,http://127.0.0.1:2381
```

### 16. kube-proxy 메트릭 설정
kube-proxy는 `Install the control plane` task에 해당한다. 만일 kube-proxy 메트릭을 수집하기 위해서는 처음에 배포가 진행되어야 할것으로 보인다. 배포 이후 진행하더라도 기존 kube-proxy CM이 수정되지 않는다.
```sh 
grep -r "kube_proxy" . |grep metric
./roles/kubernetes/control-plane/defaults/main/kube-proxy.yml:kube_proxy_metrics_bind_address: 127.0.0.1:10249
./roles/kubernetes/control-plane/templates/kubeadm-config.v1beta3.yaml.j2:metricsBindAddress: "{{ kube_proxy_metrics_bind_address }}"
./roles/kubernetes/control-plane/templates/kubeadm-config.v1beta4.yaml.j2:metricsBindAddress: "{{ kube_proxy_metrics_bind_address }}"

# 설정 변경
echo "kube_proxy_metrics_bind_address: 0.0.0.0:10249" >> inventory/mycluster/group_vars/k8s_cluster/kube_control_plane.yml

# 확인
tail -n 1 inventory/mycluster/group_vars/k8s_cluster/kube_control_plane.yml
kube_proxy_metrics_bind_address: 0.0.0.0:10249

# 기존 설정
ss -ntlp |grep 10249
LISTEN 0      4096       127.0.0.1:10249      0.0.0.0:*    users:(("kube-proxy",pid=23883,fd=11))    

# kubeadm 설정 조회
cat /etc/kubernetes/kubeadm-config.yaml | grep -i metri
metricsBindAddress: "127.0.0.1:10249"

# 배포
ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml \
  -e kube_version="1.33.3" --tags control-plane 

# 설정 변경 확인, 그러나 kube-proxy 미반영
cat /etc/kubernetes/kubeadm-config.yaml | grep -i metri
metricsBindAddress: "0.0.0.0:10249"

kubectl rollout restart ds/kube-proxy -n kube-system
kubectl get cm -n kube-system kube-proxy -o yaml | grep metricsBindAddress
    metricsBindAddress: 127.0.0.1:10249

ss -ntlp |grep 10249

# 설정 업로드 및 kube-proxy 반영
/usr/locao/bin/kubeadm init phase upload-config kubeadm --config /etc/kubernetes/kubeadm-config.yaml
/usr/locao/bin/kubeadm init phase addon kube-proxy --config /etc/kubernetes/kubeadm-config.yaml

ss -ntlp |grep 10249
LISTEN 0      4096               *:10249            *:*    users:(("kube-proxy",pid=121046,fd=12))

curl 192.168.10.10:10249/metrics
```

### 18. (notdone) ipv4 only 환경(특히 bind-address 를 `::` 이 아닌 `0.0.0.0` 으로)이 가능하게 kubespary 로 k8s 구성을 해보자.
```sh
grep -rI "::" . | grep bind_address
./roles/kubernetes/control-plane/handlers/main.yml:    endpoint: "{{ kube_scheduler_bind_addres if kube_scheduler_bind_address != '::' else 'localhost' }}"
./roles/kubernetes/control-plane/handlers/main.yml:    endpoint: "{{ kube_controller_manager_bind_address if kube_controller_manager_bind_address != '::' else 'localhost' }}"
./roles/kubernetes/node/defaults/main.yml:kubelet_bind_address: "{{ main_ip | default('::') }}"
./roles/kubernetes/node/tasks/main.yml:    - ('kube_control_plane' not in group_names) or (kube_apiserver_bind_address != '::')
./roles/kubernetes/node/tasks/main.yml:    - ('kube_control_plane' not in group_names) or (kube_apiserver_bind_address != '::')
./roles/kubespray_defaults/defaults/main/main.yml:kube_apiserver_bind_address: "::"
./roles/kubespray_defaults/defaults/main/main.yml:  https://{{ kube_apiserver_bind_address | regex_replace('::', '127.0.0.1') | ansible.utils.ipwrap }}:{{ kube_apiserver_port }}

echo "kube_apiserver_bind_address: 0.0.0.0" >> inventory/mycluster/group_vars/k8s_cluster/kube_control_plane.yml
echo "kube_scheduler_bind_addres: 0.0.0.0"  >> inventory/mycluster/group_vars/k8s_cluster/kube_control_plane.yml
echo "kube_controller_manager_bind_address: 0.0.0.0" >> inventory/mycluster/group_vars/k8s_cluster/kube_control_plane.yml

# 배포
ansible-playbook -i inventory/mycluster/inventory.ini -v cluster.yml \
  -e kube_version="1.33.3" --tags control-plane 

kubectl describe pod -n kube-system kube-apiserver-k8s-ctr | grep bind-address
      --bind-address=::
kubectl describe pod -n kube-system kube-controller-manager-k8s-ctr |grep bind-address
      --bind-address=::
kubectl describe pod -n kube-system kube-scheduler-k8s-ctr |grep bind-address
      --bind-address=::
```

### 19. Cilium으로 배포 진행하기
- `kube_network_plugin: cni`: 별도의 CNI 플러그인을 설치하지 않고 기본적인 cni 환경만 구성한다.
- `kube_owner: root`: 기존 계정인 kube 에서 root로 변환하여 별도의 권한 설정없도록 지정

```sh
sed -i 's|^kube_network_plugin:.*$|kube_network_plugin: cni|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i 's|^kube_owner:.*$|kube_owner: root|g' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
```
https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default




Ingress-Nginx 를 Kubespary 를 통해서 배포 설정 해보자.
실무 환경에 필요한 추가 sysctl 관련 커널 파라미터를 kubespary 설치 시, 적용해보자. 또한 운영을 고려한 파일 규칙과 GitOps 고민을 해보자.
Harbor 처럼 가상머신으로 내부에 ‘이미지 저장소’ 구성하고, kubespary 에 containerd 의 certs.d 에 ‘미러 저장소’를 우선 순위로 설정 테스트 정리해보자.
maxParallelImagePulls 값을 적절히 수정 후 kubelet restart 후 파드들 기동하면서 파드 기동 시간 테스트 해보자.
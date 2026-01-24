## kubeadm upgrade
" Cloudnet@ k8s Deploy 3주차 스터디를 진행하며 정리한 글입니다.

k8s 1.32 버전에서 kubeadm을 활용하여 컨트롤 플레인부터 워커 노드까지 순차적인 버전 업그레이드에 대해서 기술한 글입니다. 
1.32 -> 1.33.7, 1.33.7 -> 1.34.3 순으로 업그레이드를 진행하고자 합니다.

| 항목 | 버전 | k8s 버전 호환성 |
| --- | --- | --- |
| Rocky Linux | 10.0-1.6 | RHEL 10 소스 기반 배포판으로 RHEL 정보 참고 |
| containerd | v2.1.5 | CRI Version(v1), k8s 1.32~1.35 지원 - [Link](https://containerd.io/releases/#kubernetes-support) |
| runc | v1.3.3 | 정보 조사 필요 https://github.com/opencontainers/runc |
| kubelet | v1.32.11 | k8s 버전 정책 문서 참고 - [Docs](https://v1-32.docs.kubernetes.io/releases/version-skew-policy/) |
| kubeadm | v1.32.11 | 상동 |
| kubectl | v1.32.11 | 상동 |
| helm | v3.18.6 | k8s 1.30.x ~ 1.33.x 지원 - [Docs](https://helm.sh/docs/v3/topics/version_skew/) |
| flannel cni | v0.27.3 | k8s 1.28~ 이후 - [Release](https://github.com/flannel-io/flannel/releases) |


```sh
vagrant up
vagrant status
vagrant ssh k8s-ctr
vagrant destroy -f && rm -rf .vagrant
```

### 프로메테우스 설치 
```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

cat <<EOT > monitor-values.yaml
prometheus:
  prometheusSpec:
    scrapeInterval: "20s"
    evaluationInterval: "20s"
    externalLabels:
      cluster: "myk8s-cluster"
  service:
    type: NodePort
    nodePort: 30001

grafana:
  defaultDashboardsTimezone: Asia/Seoul
  adminPassword: prom-operator
  service:
    type: NodePort
    nodePort: 30002

alertmanager:
  enabled: true
defaultRules:
  create: true

kubeProxy:
  enabled: false
prometheus-windows-exporter:
  prometheus:
    monitor:
      enabled: false
EOT

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 80.13.3 \
  -f monitor-values.yaml --create-namespace --namespace monitoring

helm list -n monitoring
NAME                    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                             APP VERSION
kube-prometheus-stack   monitoring      1               2026-01-24 15:33:55.494415818 +0900 KST deployed        kube-prometheus-stack-80.13.3     v0.87.1

# pod 상태 확인
kubectl get pod,svc,ingress,pvc -n monitoring

# prometheus
open http://192.168.10.100:30001
# grafana
# admin / prom-operator
open http://192.168.10.100:30002 

# 프로메테우스 버전 확인
kubectl exec -it sts/prometheus-kube-prometheus-stack-prometheus -n monitoring -c prometheus -- prometheus --version
prometheus, version 3.9.1

# 그라파나 버전 확인
kubectl exec -it -n monitoring deploy/kube-prometheus-stack-grafana -- grafana --version
grafana version 12.3.1

# 그란파나 대쉬보드 추가 15661, 15757 
```

### 샘플 앱 배포
```sh
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
  type: ClusterIP
EOF


# curl 파드
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
  labels:
    app: curl
spec:
  nodeName: k8s-ctr
  containers:
  - name: curl
    image: nicolaka/netshoot
    command: ["tail"]
    args: ["-f", "/dev/null"]
  terminationGracePeriodSeconds: 0
EOF

# 앱 동작 확인 
kubectl get deploy,svc,ep webpod -owide

# 새 터미널 1 생성 후 반복 호출
SVCIP=$(kubectl get svc webpod -o jsonpath='{.spec.clusterIP}')
while true; do curl -s $SVCIP | grep Hostname; sleep 1; done

# 새 터미널 2 생성 후 반복 호출
watch -d kubectl get node

# 새 터미널 3 생성 후 반복 호출
watch -d kubectl get pod -A -owide

# 새 터미널 4 생성 후 반복 호출
watch -d kubectl top node

# 새 터미널 5 k8s-w1 생성 후 반복 호출 
watch -d crictl ps

# 새 터미널 6 k8s-w2 생성 후 반복 호출
watch -d crictl ps
```

### ETCD 백업
```sh
crictl images | grep etcd
registry.k8s.io/etcd                      3.5.24-0            1211402d28f58       21.9MB

# etcd 버전 확인
kubectl exec -n kube-system etcd-k8s-ctr -- etcdctl version
etcdctl version: 3.5.24
API version: 3.5

ETCD_VER=3.5.24

# 아키텍처에 따른 변수 지정
ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then ARCH=arm64; fi
echo $ARCH

# etcdctl 바이너리 다운로드
curl -L https://github.com/etcd-io/etcd/releases/download/v${ETCD_VER}/etcd-v${ETCD_VER}-linux-${ARCH}.tar.gz -o /tmp/etcd-v${ETCD_VER}.tar.gz
ls /tmp
etcd-download
etcd-v3.5.24.tar.gz
etcd-v.tar.gz

# 압축 해제
mkdir -p /tmp/etcd-download
tar xzvf /tmp/etcd-v${ETCD_VER}.tar.gz -C /tmp/etcd-download --strip-components=1

mv /tmp/etcd-download/etcdctl /usr/local/bin/
mv /tmp/etcd-download/etcdutl /usr/local/bin/
chown root:root /usr/local/bin/etcdctl
chown root:root /usr/local/bin/etcdutl

# etcd 버전 확인
etcdctl version
etcdctl version: 3.5.24
API version: 3.5

# etcd 수신 클라이언트 조회
kubectl describe pod -n kube-system etcd-k8s-ctr | grep isten-client-urls
      --listen-client-urls=https://127.0.0.1:2379,https://192.168.10.100:2379

# 환경변수 지정
# 환경변수를 지정하지 않더라도 명령어 실행은 가능하지만 매번 불필요한 라인이 추가된다. 이를 환경변수로 지정하면 인자를 추가하지 않더라더 etcdctl만으로 실행이 가능하다.      
export ETCDCTL_API=3  
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379 

etcdctl endpoint status -w table
+------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|        ENDPOINT        |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| https://127.0.0.1:2379 | f330bec74ce6cc42 |  3.5.24 |   20 MB |      true |      false |         2 |       4820 |               4820 |        |
+------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+

# etcd 멤버 목록 조회, HA 환경이라면 여러개의 etcd가 존재한다.
etcdctl member list -w table
+------------------+---------+---------+-----------------------------+-----------------------------+------------+
|        ID        | STATUS  |  NAME   |         PEER ADDRS          |        CLIENT ADDRS         | IS LEARNER |
+------------------+---------+---------+-----------------------------+-----------------------------+------------+
| f330bec74ce6cc42 | started | k8s-ctr | https://192.168.10.100:2380 | https://192.168.10.100:2379 |      false |
+------------------+---------+---------+-----------------------------+-----------------------------+------------+

# 백업 진행
mkdir /backup
etcdctl snapshot save /backup/etcd-snapshot-$(date +%F).db

tree /backup/
/backup/
└── etcd-snapshot-2026-01-25.db

# 스냅샷 상태 조회
etcdutl snapshot status /backup/etcd-snapshot-2026-01-25.db
3141cedb, 4717, 1602, 20 MB
```

### Flannel CNI v0.27.3 -> v0.27.4
```sh
crictl images | grep flannel
ghcr.io/flannel-io/flannel-cni-plugin     v1.7.1-flannel1     127562bd9047f       5.14MB
ghcr.io/flannel-io/flannel                v0.27.3             d84558c0144bc       33.1MB

# [k8s-ctr, k8s-w1, k8s-w2] 모든 노드에서 작업 진행 
crictl pull ghcr.io/flannel-io/flannel:v0.27.4
crictl pull ghcr.io/flannel-io/flannel-cni-plugin:v1.8.0-flannel1
ghcr.io/flannel-io/flannel                v0.27.4             24d577aa4188d       33.2MB
ghcr.io/flannel-io/flannel-cni-plugin     v1.8.0-flannel1     c6ef1e714d02a       5.17MB

# 터미널 1 
SVCIP=$(kubectl get svc webpod -o jsonpath='{.spec.clusterIP}')
while true; do curl -s $SVCIP | grep Hostname; sleep 1; done

# 터미널 2 
watch -d kubectl get pod -n kube-flannel
flannel kube-flannel    1               2026-01-25 05:27:44.314564361 +0900 KST      deployed        flannel-v0.27.3 v0.27.3    

# 기존 설정 조회
helm list -n kube-flannel
NAME    NAMESPACE       REVISION        UPDATED                                      STATUS          CHART           APP VERSION
flannel kube-flannel    1               2026-01-25 05:27:44.314564361 +0900 KST      deployed        flannel-v0.27.3 v0.27.3    

helm get values -n kube-flannel flannel
USER-SUPPLIED VALUES:
flannel:
  args:
  - --ip-masq
  - --kube-subnet-mgr
  - --iface=enp0s9
  backend: vxlan
  cniBinDir: /opt/cni/bin
  cniConfDir: /etc/cni/net.d
podCidr: 10.244.0.0/16

# 현재 flannel 버전 조회
ubectl get pod -n kube-flannel -o yaml | grep -i image: | sort | uniq
      image: ghcr.io/flannel-io/flannel-cni-plugin:v1.7.1-flannel1
      image: ghcr.io/flannel-io/flannel:v0.27.3

kubectl get ds -n kube-flannel -owide
NAME              DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE   CONTAINERS     IMAGES                               SELECTOR
kube-flannel-ds   3         3         3       3            3           <none>          50m   kube-flannel   ghcr.io/flannel-io/flannel:v0.27.3   app=flannel

cat << EOF > flannel.yaml
podCidr: "10.244.0.0/16"
flannel:
  cniBinDir: "/opt/cni/bin"
  cniConfDir: "/etc/cni/net.d"
  args:
  - "--ip-masq"
  - "--kube-subnet-mgr"
  - "--iface=enp0s9"  
  backend: "vxlan"
image:
  tag: v0.27.4
EOF

# 신규 배포 
helm upgrade flannel flannel/flannel -n kube-flannel -f flannel.yaml --version 0.27.4

kubectl -n kube-flannel rollout status ds/kube-flannel-ds

helm list -n kube-flannel
flannel kube-flannel    2               2026-01-25 06:18:16.000759639 +0900 KST deployed    flannel-v0.27.4  v0.27.4    

helm get values -n kube-flannel flannel
USER-SUPPLIED VALUES:
flannel:
  args:
  - --ip-masq
  - --kube-subnet-mgr
  - --iface=enp0s9
  backend: vxlan
  cniBinDir: /opt/cni/bin
  cniConfDir: /etc/cni/net.d
image:
  tag: v0.27.4
podCidr: 10.244.0.0/16

crictl ps |grep flannel
218d3b5fa95b2       24d577aa4188d       3 minutes ago       Running             kube-flannel              0                   e7ee3a80758a5       kube-flannel-ds-bq9l5                                  kube-flannel

kubectl get ds -n kube-flannel -owide
kube-flannel-ds   3         3         3       3            3           <none>          55m   kube-flannel   ghcr.io/flannel-io/flannel:v0.27.4   app=flannel

kubectl get pod -n kube-flannel -o yaml | grep -i image: | sort | uniq
      image: ghcr.io/flannel-io/flannel-cni-plugin:v1.8.0-flannel1
      image: ghcr.io/flannel-io/flannel:v0.27.4
```

### OS 업그레이드 rocky 10.0 -> 10.1
```sh
kubectl get pod -A -owide |grep k8s-ctr
default        curl-pod                                                    1/1     Running   0          57m   10.244.0.4       k8s-ctr   <none>           <none>
kube-flannel   kube-flannel-ds-bq9l5                                       1/1     Running   0          14m   192.168.10.100   k8s-ctr   <none>           <none>
kube-system    coredns-668d6bf9bc-fr8lg                                    1/1     Running   0          65m   10.244.0.3       k8s-ctr   <none>           <none>
kube-system    coredns-668d6bf9bc-nctbg                                    1/1     Running   0          65m   10.244.0.2       k8s-ctr   <none>           <none>
kube-system    etcd-k8s-ctr                                                1/1     Running   0          65m   192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-apiserver-k8s-ctr                                      1/1     Running   0          65m   192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-controller-manager-k8s-ctr                             1/1     Running   0          65m   192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-proxy-mxjd2                                            1/1     Running   0          65m   192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-scheduler-k8s-ctr                                      1/1     Running   0          65m   192.168.10.100   k8s-ctr   <none>           <none>
monitoring     kube-prometheus-stack-prometheus-node-exporter-rg27z        1/1     Running   0          61m   192.168.10.100   k8s-ctr   <none>           <none>

# coredns 분산 배포, 현재 coredns가 k8s-ctr에만 존재하기 떄문에 노드 중단에 따른 영향도를 최소화하기 위해서 분산 배포 진행
k scale deployment -n kube-system coredns --replicas 1

kubectl get pod -A -owide |grep k8s-ctr
kube-system    coredns-668d6bf9bc-nctbg                                    1/1     Running   0          67m   10.244.0.2       k8s-ctr   <none>           <none>

kubectl scale deployment -n kube-system coredns --replicas 2

kubectl get pod -n kube-system -owide | grep coredns
coredns-668d6bf9bc-7mm8v          1/1     Running   0          63s   10.244.1.7       k8s-w1    <none>           <none>
coredns-668d6bf9bc-nctbg          1/1     Running   0          67m   10.244.0.2       k8s-ctr   <none>           <none>

# 새 터미널 1, k8s-w1
SVCIP=$(kubectl get svc webpod -o jsonpath='{.spec.clusterIP}')
kubectl exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'

rpm -aq | grep release 
rocky-release-10.0-1.6.el10.noarch

uname -r 
6.12.0-55.39.1.el10_0.aarch64

rpm -q containerd.io
containerd.io-2.1.5-1.el10.aarch64

# 업데이트시 특정 패키지 버전 락 플러그인 설치
dnf install -y 'dnf-command(versionlock)'

# containrd 락
dnf versionlock add containerd.io
Adding versionlock on: containerd.io-0:2.1.5-1.el10.*

dnf versionlock list
containerd.io-0:2.1.5-1.el10.*

dnf -y update 

# CP 1대 환경이기에 당연히 api-server 통신 불가
reboot

vagrant ssh k8s-ctr
rpm -aq | grep release 
rocky-release-10.1-1.4.el10.noarch

uname -r              
6.12.0-124.28.1.el10_1.aarch64 

kubectl get pod -A -owide |grep k8s-ctr
default        curl-pod                                                    1/1     Running   1 (44s ago)   65m     10.244.0.3       k8s-ctr   <none>           <none>
kube-flannel   kube-flannel-ds-bq9l5                                       1/1     Running   1 (44s ago)   23m     192.168.10.100   k8s-ctr   <none>           <none>
kube-system    coredns-668d6bf9bc-nctbg                                    1/1     Running   1 (44s ago)   74m     10.244.0.2       k8s-ctr   <none>           <none>
kube-system    etcd-k8s-ctr                                                1/1     Running   1 (44s ago)   74m     192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-apiserver-k8s-ctr                                      1/1     Running   1 (44s ago)   74m     192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-controller-manager-k8s-ctr                             1/1     Running   1 (44s ago)   74m     192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-proxy-mxjd2                                            1/1     Running   1 (44s ago)   74m     192.168.10.100   k8s-ctr   <none>           <none>
kube-system    kube-scheduler-k8s-ctr                                      1/1     Running   1 (44s ago)   74m     192.168.10.100   k8s-ctr   <none>           <none>
monitoring     kube-prometheus-stack-prometheus-node-exporter-rg27z        1/1     Running   1 (44s ago)   70m     192.168.10.100   k8s-ctr   <none>           <none>
```

### k8s-ctr Kubeadm , Kubelet, Kubectl 1.32.11 -> v1.33.7
```sh
# repo 업데이트
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# 캐시 초기화
dnf makecache

# 설치 가능 버전 조회
dnf list --showduplicates kubeadm --disableexcludes=kubernetes

dnf install -y --disableexcludes=kubernetes kubeadm-1.33.7-150500.1.1
Upgraded:
  kubeadm-1.33.7-150500.1.1.aarch64                                

which kubeadm && kubeadm version -o yaml
/usr/bin/kubeadm
clientVersion:
  buildDate: "2025-12-09T14:41:01Z"
  compiler: gc
  gitCommit: a7245cdf3f69e11356c7e8f92b3e78ca4ee4e757
  gitTreeState: clean
  gitVersion: v1.33.7
  goVersion: go1.24.11
  major: "1"
  minor: "33"
  platform: linux/arm64


# dry-run으로 향후 업그레이드 가능한 버전, 여파에 대해서 출력해준다.
kubeadm upgrade plan
[preflight] Running pre-flight checks.
[upgrade/config] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[upgrade/config] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.
[upgrade] Running cluster health checks
[upgrade] Fetching available versions to upgrade to
[upgrade/versions] Cluster version: 1.32.11
[upgrade/versions] kubeadm version: v1.33.7
I0125 06:44:52.662441    8152 version.go:261] remote version is much newer: v1.35.0; falling back to: stable-1.33
[upgrade/versions] Target version: v1.33.7
[upgrade/versions] Latest version in the v1.32 series: v1.32.11

Components that must be upgraded manually after you have upgraded the control plane with 'kubeadm upgrade apply':
COMPONENT   NODE      CURRENT    TARGET
kubelet     k8s-ctr   v1.32.11   v1.33.7
kubelet     k8s-w1    v1.32.11   v1.33.7
kubelet     k8s-w2    v1.32.11   v1.33.7

Upgrade to the latest stable version:

COMPONENT                 NODE      CURRENT    TARGET
kube-apiserver            k8s-ctr   v1.32.11   v1.33.7
kube-controller-manager   k8s-ctr   v1.32.11   v1.33.7
kube-scheduler            k8s-ctr   v1.32.11   v1.33.7
kube-proxy                          1.32.11    v1.33.7
CoreDNS                             v1.11.3    v1.12.0
etcd                      k8s-ctr   3.5.24-0   3.5.24-0

You can now apply the upgrade by executing the following command:

        kubeadm upgrade apply v1.33.7

The table below shows the current state of component configs as understood by this version of kubeadm.
Configs that have a "yes" mark in the "MANUAL UPGRADE REQUIRED" column require manual config upgrade or
resetting to kubeadm defaults before a successful upgrade can be performed. The version to manually
upgrade to is denoted in the "PREFERRED VERSION" column.

API GROUP                 CURRENT VERSION   PREFERRED VERSION   MANUAL UPGRADE REQUIRED
kubeproxy.config.k8s.io   v1alpha1          v1alpha1            no
kubelet.config.k8s.io     v1beta1           v1beta1             no


# 새 터미널 1, k8s-w1 작업 진행
SVCIP=$(kubectl get svc webpod -o jsonpath='{.spec.clusterIP}')
kubectl exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'

# 새 터미널2
watch -d kubectl get node

# 새 터미널3
watch -d kubectl get pod -n kube-system

# 터미널 4
watch -d etcdctl member list -w table

# 이미지 pre-download, 작업시간 단축을 위함
kubeadm config images pull

crictl images |grep 1.33.7
registry.k8s.io/kube-apiserver            v1.33.7             6d7bc8e445519       27.4MB
registry.k8s.io/kube-controller-manager   v1.33.7             a94595d0240bc       25.1MB
registry.k8s.io/kube-proxy                v1.33.7             78ccb937011a5       28.3MB
registry.k8s.io/kube-scheduler            v1.33.7             94005b6be50f0       19.9MB
registry.k8s.io/coredns/coredns           v1.12.0             f72407be9e08c       19.1MB

# kube-proxy와 coredns는 모든 노드에서 작업 진행
crictl pull registry.k8s.io/kube-proxy:v1.33.7
crictl pull registry.k8s.io/coredns/coredns:v1.12.0

# CP 버전 업글레이드, cp 컴포넌트 컨테이너 이미지 업그레이드
kubeadm upgrade apply v1.33.7

# kubelet은 업데이트되지 않아 예전 버전으로 출력된다.
kubectl get node -owide
k8s-ctr   Ready    control-plane   86m   v1.32.11   192.168.10.100   <none>        Rocky Linux 10.1 (Red Quartz)   6.12.0-124.28.1.el10_1.aarch64   containerd://2.1.5

kubectl describe node k8s-ctr | grep 'Kubelet Version:'
  Kubelet Version:            v1.32.11

kubectl get pod -A

crictl images

ls -l /etc/kubernetes/manifests/
-rw-------. 1 root root 2576 Jan 25 06:48 etcd.yaml
-rw-------. 1 root root 3602 Jan 25 06:48 kube-apiserver.yaml
-rw-------. 1 root root 3053 Jan 25 06:48 kube-controller-manager.yaml
-rw-------. 1 root root 1582 Jan 25 06:48 kube-scheduler.yaml

# 버전 업그레이드 확인
cat /etc/kubernetes/manifests/*.yaml | grep -i image:
    image: registry.k8s.io/etcd:3.5.24-0
    image: registry.k8s.io/kube-apiserver:v1.33.7
    image: registry.k8s.io/kube-controller-manager:v1.33.7
    image: registry.k8s.io/kube-scheduler:v1.33.7

kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}  - {.name}: {.image}{"\n"}{end}{"\n"}{end}'
oredns-674b8bbfcf-2dcww
  - coredns: registry.k8s.io/coredns/coredns:v1.12.0
coredns-674b8bbfcf-hk6xp
  - coredns: registry.k8s.io/coredns/coredns:v1.12.0
etcd-k8s-ctr
  - etcd: registry.k8s.io/etcd:3.5.24-0
kube-apiserver-k8s-ctr
  - kube-apiserver: registry.k8s.io/kube-apiserver:v1.33.7
kube-controller-manager-k8s-ctr
  - kube-controller-manager: registry.k8s.io/kube-controller-manager:v1.33.7
kube-proxy-fpvlq
  - kube-proxy: registry.k8s.io/kube-proxy:v1.33.7
kube-proxy-jtp8
  - kube-proxy: registry.k8s.io/kube-proxy:v1.33.7
kube-proxy-wrmhm
  - kube-proxy: registry.k8s.io/kube-proxy:v1.33.7
kube-scheduler-k8s-ctr
  - kube-scheduler: registry.k8s.io/kube-scheduler:v1.33.7


# kubelet, kubectl 설치 가능 벚너 출력 
dnf list --showduplicates kubelet --disableexcludes=kubernetes
dnf list --showduplicates kubectl --disableexcludes=kubernetes

# ubelet, kubectl 업글레이드
dnf install -y --disableexcludes=kubernetes kubelet-1.33.7-150500.1.1 kubectl-1.33.7-150500.1.1

which kubectl && kubectl version --client=true
v1.33.7

which kubelet && kubelet --version
Kubernetes v1.33.7

# 재시작 동안 일부 다운타임 발생
systemctl daemon-reload
systemctl restart kubelet 

# 버전 업그레이드 확인
kubectl get nodes -o wide
k8s-ctr   Ready    control-plane   90m   v1.33.7    192.168.10.100   <none>        Rocky Linux 10.1 (Red Quartz)   6.12.0-124.28.1.el10_1.aarch64   containerd://2.1.5

kubectl describe node k8s-ctr | grep 'Kubelet Version:'
  Kubelet Version:            v1.33.7
```
### k8s-ctr Kubeadm , Kubelet, Kubectl 1.33.7 -> v1.34.3
```sh
# 앞선 작업과 동일하게 수행, 버전만 다르다
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
dnf makecache

dnf list --showduplicates kubeadm --disableexcludes=kubernetes
dnf install -y --disableexcludes=kubernetes kubeadm-1.34.3-150500.1.1

which kubeadm && kubeadm version -o yaml
/usr/bin/kubeadm
clientVersion:
  buildDate: "2025-12-09T15:05:15Z"
  compiler: gc
  gitCommit: df11db1c0f08fab3c0baee1e5ce6efbf816af7f1
  gitTreeState: clean
  gitVersion: v1.34.3
  goVersion: go1.24.11
  major: "1"
  minor: "34"
  platform: linux/arm64

kubeadm upgrade plan
COMPONENT                 NODE      CURRENT    TARGET
kube-apiserver            k8s-ctr   v1.33.7    v1.34.3
kube-controller-manager   k8s-ctr   v1.33.7    v1.34.3
kube-scheduler            k8s-ctr   v1.33.7    v1.34.3
kube-proxy                          1.33.7     v1.34.3
CoreDNS                             v1.12.0    v1.12.1
etcd                      k8s-ctr   3.5.24-0   3.6.5-0

You can now apply the upgrade by executing the following command:

        kubeadm upgrade apply v1.34.3

The table below shows the current state of component configs as understood by this version of kubeadm.
Configs that have a "yes" mark in the "MANUAL UPGRADE REQUIRED" column require manual config upgrade or
resetting to kubeadm defaults before a successful upgrade can be performed. The version to manually
upgrade to is denoted in the "PREFERRED VERSION" column.

API GROUP                 CURRENT VERSION   PREFERRED VERSION   MANUAL UPGRADE REQUIRED
kubeproxy.config.k8s.io   v1alpha1          v1alpha1            no
kubelet.config.k8s.io     v1beta1           v1beta1             no

# 이미지 pre-download
kubeadm config images pull
crictl images

# 모든 워커 노드에서 동일한 작업 수행
crictl pull registry.k8s.io/kube-proxy:v1.34.3
crictl pull registry.k8s.io/coredns/coredns:v1.12.1
crictl pull registry.k8s.io/pause:3.10.1

# 버전 업그레이드
kubeadm upgrade apply v1.34.3 --yes

# kubelet 버전 확인
kubectl get node -owide
kubectl describe node k8s-ctr | grep 'Kubelet Version:'
  Kubelet Version:            v1.33.7

# CP 컨테이너 이미지 변경 확인
cat /etc/kubernetes/manifests/*.yaml | grep -i image:
kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}  - {.name}: {.image}{"\n"}{end}{"\n"}{end}'
coredns-66bc5c9577-98n28
  - coredns: registry.k8s.io/coredns/coredns:v1.12.1
coredns-66bc5c9577-vq8tk
  - coredns: registry.k8s.io/coredns/coredns:v1.12.1
etcd-k8s-ctr
  - etcd: registry.k8s.io/etcd:3.6.5-0
kube-apiserver-k8s-ctr
  - kube-apiserver: registry.k8s.io/kube-apiserver:v1.34.3
kube-controller-manager-k8s-ctr
  - kube-controller-manager: registry.k8s.io/kube-controller-manager:v1.34.3
kube-proxy-64s8f
  - kube-proxy: registry.k8s.io/kube-proxy:v1.34.3
kube-proxy-j9tp8
  - kube-proxy: registry.k8s.io/kube-proxy:v1.33.7
kube-proxy-wrmhm
  - kube-proxy: registry.k8s.io/kube-proxy:v1.33.7
kube-scheduler-k8s-ctr
  - kube-scheduler: registry.k8s.io/kube-scheduler:v1.34.3
metrics-server-5dd7b49d79-xzbx2
  - metrics-server: registry.k8s.io/metrics-server/metrics-server:v0.8.0

# kubelet, kubectl 업글레이드
dnf install -y --disableexcludes=kubernetes kubelet-1.34.3-150500.1.1 kubectl-1.34.3-150500.1.1

# 버전 확인
which kubectl && kubectl version --client=true
/usr/bin/kubectl
Client Version: v1.34.3
Kustomize Version: v5.7.1

which kubelet && kubelet --version
/usr/bin/kubelet
Kubernetes v1.34.3

# 재시작 
systemctl daemon-reload   
systemctl restart kubelet 

# 버전 확인
kubectl get nodes -o wide
k8s-ctr   Ready    control-plane   100m   v1.34.3    192.168.10.100   <none>        Rocky Linux 10.1 (Red Quartz)   6.12.0-124.28.1.el10_1.aarch64   containerd://2.1.5
kc describe node k8s-ctr
kubectl describe node k8s-ctr | grep 'Kubelet Version:'
  Kubelet Version:            v1.34.3

# kubeconfig 업데이트
# 작업하는 사용자와 admin 설정 파일 경로 조회
ls -l ~/.kube/config
-rw-------. 1 root root 5618 Jan 25 05:27 /root/.kube/config

ls -l /etc/kubernetes/admin.conf 
-rw-------. 1 root root 5642 Jan 25 07:05 /etc/kubernetes/admin.conf

# 복사
yes | cp  /etc/kubernetes/admin.conf ~/.kube/config ; echo

# 권한 변경
chown $(id -u):$(id -g) ~/.kube/config

# 컨텍스트명 변경
kubectl config rename-context "kubernetes-admin@kubernetes" "HomeLab"

kubens default

# pause 컨테이너 신규 이미지 적용
ps -ef | grep -i pause | grep kubelet | grep pause
root       21980       1  2 07:06 ?        00:00:04 /usr/bin/kubelet --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml --node-ip=192.168.10.100 --pod-infra-container-image=registry.k8s.io/pause:3.10

# 새 버전이 존재하지만 예전 버전인 3.10을 사용중이다.
crictl images | grep pause
registry.k8s.io/pause                     3.10                afb61768ce381       268kB
registry.k8s.io/pause                     3.10.1              d7b100cd9a77b       268kB

cat /etc/containerd/config.toml  | grep -i pause:
      sandbox = 'registry.k8s.io/pause:3.10'

# 설정 변경
sed -i 's/pause:3.10/pause:3.10.1/g' /etc/containerd/config.toml

cat /etc/containerd/config.toml  | grep -i pause:
      sandbox = 'registry.k8s.io/pause:3.10.1'

# kubelet 설정 확인
cat /var/lib/kubelet/kubeadm-flags.env
KUBELET_KUBEADM_ARGS="--node-ip=192.168.10.100 --pod-infra-container-image=registry.k8s.io/pause:3.10"

# 3.10. -> 3.10.1
vi /var/lib/kubelet/kubeadm-flags.env
KUBELET_KUBEADM_ARGS="--node-ip=192.168.10.100 --pod-infra-container-image=registry.k8s.io/pause:3.10.1"

# 컨테이너D 설정 반영을 위한 재시작
systemctl restart kubelet.service
systemctl status kubelet.service --no-pager

kubectl delete pod curl-pod

# test
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
  labels:
    app: curl
spec:
  nodeName: k8s-ctr
  containers:
  - name: curl
    image: nicolaka/netshoot
    command: ["tail"]
    args: ["-f", "/dev/null"]
  terminationGracePeriodSeconds: 0
EOF

ctr -n k8s.io containers list | grep pause
```

### 워커 노드 Kubeadm , Kubelet, Kubectl 1.32.11 -> v1.33.7
```sh
# 데이터 유실 가능한 파드로 인해 워커 노드 1번 부터 진행
kubectl get pod -A -owide | grep k8s-w1
kubectl get pod -A -owide | grep k8s-w2
monitoring     kube-prometheus-stack-grafana-5cb7c586f9-6kfgx              3/3     Running   0              108m    10.244.2.4       k8s-w2    <none>           <none>
monitoring     prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0              108m    10.244.2.5       k8s-w2    <none>           <none>

kubectl get sts -A
NAMESPACE    NAME                                              READY   AGE
monitoring   alertmanager-kube-prometheus-stack-alertmanager   1/1     109m
monitoring   prometheus-kube-prometheus-stack-prometheus       1/1     109m

# 별도의 pvd와 pvc가 없어서 데이터가 유실된다
kubectl get pv,pvc -A
No resources found

# webpod에 PB 적용
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
webpod   N/A             0                 0                     15s

# 새 터미널 1 
SVCIP=$(kubectl get svc webpod -o jsonpath='{.spec.clusterIP}')
kubectl exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'

# 새 터미널 2
watch -d kubectl get node

# 새 터미널 3
watch -d kubectl get pod

# 워커 노드 1 드레인 
kubectl drain k8s-w1
error: unable to drain node "k8s-w1" due to error: [cannot delete Pods with local storage (use --delete-emptydir-data to override): kube-system/metrics-server-5dd7b49d79-xzbx2, monitoring/alertmanager-kube-prometheus-stack-alertmanager-0, cannot delete DaemonSet-managed Pods (use --ignore-daemonsets to ignore): kube-flannel/kube-flannel-ds-5nxqs, kube-system/kube-proxy-64s8f, monitoring/kube-prometheus-stack-prometheus-node-exporter-hkhvc], continuing command...

kubectl get node
NAME      STATUS                     ROLES           AGE    VERSION
k8s-ctr   Ready                      control-plane   116m   v1.34.3
k8s-w1    Ready,SchedulingDisabled   <none>          114m   v1.32.11
k8s-w2    Ready                      <none>          113m   v1.32.11

kubectl get pod -A -owide |grep k8s-w1
default        webpod-697b545f57-c22d8                                     1/1     Running   0              108m    10.244.1.6       k8s-w1    <none>           <none>
kube-flannel   kube-flannel-ds-5nxqs                                       1/1     Running   0              65m     192.168.10.101   k8s-w1    <none>           <none>
kube-system    coredns-66bc5c9577-98n28                                    1/1     Running   0              18m     10.244.1.8       k8s-w1    <none>           <none>
kube-system    kube-proxy-64s8f                                            1/1     Running   0              18m     192.168.10.101   k8s-w1    <none>           <none>
kube-system    metrics-server-5dd7b49d79-xzbx2                             1/1     Running   0              116m    10.244.1.2       k8s-w1    <none>           <none>
monitoring     alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0              112m    10.244.1.5       k8s-w1    <none>           <none>
monitoring     kube-prometheus-stack-operator-584f446c98-dfszd             1/1     Running   0              112m    10.244.1.3       k8s-w1    <none>           <none>
monitoring     kube-prometheus-stack-prometheus-node-exporter-hkhvc        1/1     Running   0              112m    192.168.10.101   k8s-w1    <none>           <none>

# PDB로 인해 추출이 안된다
kubectl drain k8s-w1 --ignore-daemonsets --delete-emptydir-data
error when evicting pods/"webpod-697b545f57-c22d8" -n "default" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.'

kubectl get pod -A -owide |grep k8s-w1

# pdb 제거 후 진행
kubectl delete pdb webpod

kubectl drain k8s-w1 --ignore-daemonsets --delete-emptydir-data
node/k8s-w1 drained

kubectl get node
NAME      STATUS                     ROLES           AGE    VERSION
k8s-ctr   Ready                      control-plane   118m   v1.34.3
k8s-w1    Ready,SchedulingDisabled   <none>          116m   v1.32.11
k8s-w2    Ready                      <none>          115m   v1.32.11

# 더이상 파드가 스케줄되지 않는다.
kc describe node k8s-w1 |grep -i taint
Taints:             node.kubernetes.io/unschedulable:NoSchedule

vagrant ssh k8s-w1

# 레포지토리 업데이트
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf makecache

dnf install -y --disableexcludes=kubernetes kubeadm-1.33.7-150500.1.1

which kubeadm && kubeadm version -o yaml
/usr/bin/kubeadm
clientVersion:
  buildDate: "2025-12-09T14:41:01Z"
  compiler: gc
  gitCommit: a7245cdf3f69e11356c7e8f92b3e78ca4ee4e757
  gitTreeState: clean
  gitVersion: v1.33.7
  goVersion: go1.24.11
  major: "1"
  minor: "33"
  platform: linux/arm64

# 노드 업글레이드
kubeadm upgrade node

# kubelet, kubectl 설치 가능 버전 조회
dnf list --showduplicates kubelet --disableexcludes=kubernetes
dnf list --showduplicates kubectl --disableexcludes=kubernetes

# kubelet, kubectl 설치
dnf install -y --disableexcludes=kubernetes kubelet-1.33.7-150500.1.1 kubectl-1.33.7-150500.1.1

# 버전 확인
which kubectl && kubectl version --client=true
/usr/bin/kubectl
Client Version: v1.33.7
Kustomize Version: v5.6.0

which kubelet && kubelet --version
/usr/bin/kubelet
Kubernetes v1.33.7

# 재시간
systemctl daemon-reload
systemctl restart kubelet
systemctl status kubelet --no-pager

# 데몬셋 상태 조회
crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                                                    NAMESPACE
689183fe98ca5       4461daf6b6af8       23 minutes ago      Running             kube-proxy          0                   4b70232b1b0fd       kube-proxy-64s8f                                       kube-system
11da062211416       24d577aa4188d       About an hour ago   Running             kube-flannel        0                   339941d6cda17       kube-flannel-ds-5nxqs                                  kube-flannel
d450f7c9767ba       6b5bc413b280c       2 hours ago         Running             node-exporter       0                   9c661dd0b81e5       kube-prometheus-stack-prometheus-node-exporter-hkhvc   monitorin

# 버전은 올랐지만 아직 파드가 스케줄되지는 않는다.
kubectl get nodes -o wide
k8s-w1    Ready,SchedulingDisabled   <none>          122m   v1.33.7    192.168.10.101   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.aarch64    containerd://2.1.5
```

### 워커 노드 Kubeadm , Kubelet, Kubectl 1.33.7 -> v1.34.3
```sh
# 이전과 동일한 작업 수행
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
dnf makecache

dnf install -y --disableexcludes=kubernetes kubeadm-1.34.3-150500.1.1

which kubeadm && kubeadm version -o yaml
  gitVersion: v1.34.3

kubeadm upgrade node

dnf install -y --disableexcludes=kubernetes kubelet-1.34.3-150500.1.1 kubectl-1.34.3-150500.1.1

systemctl daemon-reload
systemctl restart kubelet
systemctl status kubelet --no-pager

crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                                                    NAMESPACE
689183fe98ca5       4461daf6b6af8       28 minutes ago      Running             kube-proxy          0                   4b70232b1b0fd       kube-proxy-64s8f                                       kube-system
11da062211416       24d577aa4188d       About an hour ago   Running             kube-flannel        0                   339941d6cda17       kube-flannel-ds-5nxqs                                  kube-flannel
d450f7c9767ba       6b5bc413b280c       2 hours ago         Running             node-exporter       0                   9c661dd0b81e5       kube-prometheus-stack-prometheus-node-exporter-hkhvc   monitoring

kubectl get nodes -o wide
k8s-w1    Ready,SchedulingDisabled   <none>          125m   v1.34.3    192.168.10.101   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.aarch64    containerd://2.1.5

# 노드 uncordon 진행
kubectl uncordon k8s-w1

# 상태 확인
k8s-w1    Ready    <none>          126m   v1.34.3    192.168.10.101   <none>        Rocky Linux 10.0 (Red Quartz)   6.12.0-55.39.1.el10_0.aarch64    containerd://2.1.5

# 파드 스케쥴링 확인
kubectl scale deployment webpod --replicas 1
kubectl get pod -owide
NAME                      READY   STATUS    RESTARTS   AGE    IP            NODE      NOMINATED NODE   READINESS GATES
curl-pod                  1/1     Running   0          20m    10.244.0.12   k8s-ctr   <none>           <none>
webpod-697b545f57-7swdp   1/1     Running   0          119m   10.244.2.6    k8s-w2    <none> 

kubectl scale deployment webpod --replicas 2
kubectl get pod -owide
NAME                      READY   STATUS    RESTARTS   AGE    IP            NODE      NOMINATED NODE   READINESS GATES
curl-pod                  1/1     Running   0          20m    10.244.0.12   k8s-ctr   <none>           <none>
webpod-697b545f57-7swdp   1/1     Running   0          119m   10.244.2.6    k8s-w2    <none>           <none>
webpod-697b545f57-trr2n   1/1     Running   0          5s     10.244.1.9    k8s-w1    <none> 


# k8s-ctr과 동일한 puase 컨테이너 신규 버전 적용
ps -ef | grep -i pause | grep kubelet | grep pause
root       34596       1  1 07:33 ?        00:00:02 /usr/bin/kubelet --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml --node-ip=192.168.10.101 --pod-infra-container-image=registry.k8s.io/pause:3.10

# 새 버전이 존재하지만 예전 버전인 3.10을 사용중이다.
crictl images | grep pause
registry.k8s.io/pause                     3.10                afb61768ce381       268kB
registry.k8s.io/pause                     3.10.1              d7b100cd9a77b       268kB

cat /etc/containerd/config.toml  | grep -i pause:
      sandbox = 'registry.k8s.io/pause:3.10'

# 설정 변경
sed -i 's/pause:3.10/pause:3.10.1/g' /etc/containerd/config.toml

cat /etc/containerd/config.toml  | grep -i pause:
      sandbox = 'registry.k8s.io/pause:3.10.1'

# kubelet 설정 확인
cat /var/lib/kubelet/kubeadm-flags.env
KUBELET_KUBEADM_ARGS="--node-ip=192.168.10.100 --pod-infra-container-image=registry.k8s.io/pause:3.10"

# 3.10. -> 3.10.1
vi /var/lib/kubelet/kubeadm-flags.env
KUBELET_KUBEADM_ARGS="--node-ip=192.168.10.100 --pod-infra-container-image=registry.k8s.io/pause:3.10.1"

# 컨테이너D 설정 반영을 위한 재시작
systemctl restart kubelet.service
systemctl status kubelet.service --no-pager
```

### 워커 노드 rest 및 join
```sh
# 
kubectl drain k8s-w1 --ignore-daemonsets --delete-emptydir-data

# 노드 삭제
kubectl delete node k8s-w1

# 노드 상태 확인
kubectl get node
NAME      STATUS   ROLES           AGE    VERSION
k8s-ctr   Ready    control-plane   138m   v1.34.3
k8s-w2    Ready    <none>          135m   v1.32.11

vagrant ssh k8s-w1

kubeadm reset -f
[preflight] Running pre-flight checks
W0125 07:45:52.419458   37874 removeetcdmember.go:105] [reset] No kubeadm config, using etcd pod spec to get data directory
[reset] Deleted contents of the etcd data directory: /var/lib/etcd
[reset] Stopping the kubelet service
[reset] Unmounting mounted directories in "/var/lib/kubelet"
[reset] Deleting contents of directories: [/etc/kubernetes/manifests /var/lib/kubelet /etc/kubernetes/pki]
[reset] Deleting files: [/etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf]

The reset process does not perform cleanup of CNI plugin configuration,
network filtering rules and kubeconfig files.

For information on how to perform this cleanup manually, please see:
    https://k8s.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/


tree /etc/kubernetes/
/etc/kubernetes/
├── manifests
├── pki
└── tmp
    ├── kubeadm-kubelet-config1987008299
    │   └── config.yaml
    └── kubeadm-kubelet-config3029781220
        └── config.yaml

tree /var/lib/kubelet/
/var/lib/kubelet/

tree /etc/cni
/etc/cni
└── net.d
    └── 10-flannel.conflist

# 기존 설정 전부 삭제
rm -rf /etc/cni/net.d
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet
# 컨트롤 플레인 노드일 경우 etcd도 추가 삭제
rm -rf /var/lib/etcd   

# iptalbes 초기화
iptables -t nat -S
iptables -t filter -S
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# 컨테이너D는 삭제하지 않으
systemctl status containerd --no-pager 
systemctl status kubelet --no-pager

systemctl stop kubelet && systemctl disable kubelet
systemctl stop containerd && systemctl disable containerd

reboot

# k8s-ctr에서 토큰 생성
kubeadm token create --print-join-command

# k8s-w1 워커에서 join 실행
kubeadm join 192.168.10.100:6443 --token 5anzrg.tis5bnnssa8vl0zi --discovery-token-ca-cert-hash sha256:9690db2d44d8440d579bc914daac4c2736254564309517b853912a10b91222e4 

# 노드 조회
kubectl get nodes -o wide 
```

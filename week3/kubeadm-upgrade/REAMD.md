### kubeadm upgrade

```sh
vagrant up
vagrant status
vagrant destroy -f && rm -rf .vagrant
```


### 프로메테우스 설치 
```sh

vagrant ssh k8s-ctr

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

kubectl get pod,svc,ingress,pvc -n monitoring
kubectl get prometheus,servicemonitors,alertmanagers -n monitoring
kubectl get crd | grep monitoring


# prometheus
open http://192.168.10.100:30001
# grafana
# admin / prom-operator
open http://192.168.10.100:30002 


kubectl exec -it sts/prometheus-kube-prometheus-stack-prometheus -n monitoring -c prometheus -- prometheus --version
prometheus, version 3.9.1 (branch: HEAD, revision: 9ec59baffb547e24f1468a53eb82901e58feabd8)

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


# k8s-ctr 노드에 curl-pod 파드 배포
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
# 배포 확인
kubectl get deploy,svc,ep webpod -owide

# 반복 호출
kubectl exec -it curl-pod -- curl webpod | grep Hostname
kubectl exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'
혹은
SVCIP=$(kubectl get svc webpod -o jsonpath='{.spec.clusterIP}')
while true; do curl -s $SVCIP | grep Hostname; sleep 1; done


# 터미널1
SVCIP=$(kubectl get svc webpod -o jsonpath='{.spec.clusterIP}')
while true; do curl -s $SVCIP | grep Hostname; sleep 1; done
혹은
kubectl exec -it curl-pod -- sh -c 'while true; do curl -s --connect-timeout 1 webpod | grep Hostname; echo "---" ; sleep 1; done'

# 터미널2
watch -d kubectl get node

# 터미널3
watch -d kubectl get pod -A -owide

# 터미널4
watch -d kubectl top node

# 터미널5
[k8s-w1] watch -d crictl ps

# 터미널6
[k8s-w2] watch -d crictl ps

```
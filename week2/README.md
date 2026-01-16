### Ansible 
" Cloudnet@ k8s Deploy 2주차 스터디를 진행하며 정리한 글입니다.

Ansible이란 자동화 도구로서 코드 기반으로 인프라 설정을 구성하는 도구이다. 

특징
- 멱등성
- 자동화
- SSH을 통한 서버 관리
- 별도의 에이전트 없이 python으로 작업 수행 
- 손쉬운 사용 및 다양한 모듈 제공

요소 
- 컨트롤 노드
- 관리 노드 
- 인벤토리: 컨트를 노드가 관리하고자 하는 관리 노드에 대한 목록
- 모듈: 관리 노드가 작업할 때 ssh 연결 한후 `앤서블 모듈`이라 하는 스크립트를 푸시하여 동작한다.
- 플러그인: 컨트롤 노드에서 실행되며, 핵심 기능(데이터 변환, 로그 출력, 인벤토리 연결)과 같은 확장 기능 수행
- 플레이북: YAML을 이용한 관리 노드에서 수행항 순차적인 작업들에 대한 정의 

### Vagrant 기본 설정

| Node | OS | Kernel | vCPU | Memory | Disk | NIC2 IP | 관리자 계정 | (기본) 일반 계정 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| server | Ubuntu 24.04 | 6.8.0 | 2 | 1.5GB | 30GB | 10.10.1.10 | root / qwe123 | vagrant / qwe123 |
| tnode1 | 상동 | 상동 | 2 | 1.5GB | 30GB | 10.10.1.11 | root / qwe123 | vagrant / qwe123 |
| tnode2 | 상동 | 상동 | 2 | 1.5GB | 30GB | 10.10.1.12 | root / qwe123 | vagrant / qwe123 |
| tnode3 | Rocky Linux 9 | 5.14.0 | 2 | 1.5GB | 60GB | 10.10.1.13 | root / qwe123 | vagrant / qwe123 |

```sh
vagrant up

# 서버 접속
vagrant ssh server

# /etc/hosts 확인
cat /etc/hosts
10.10.1.10 server
10.10.1.11 tnode1
10.10.1.12 tnode2
10.10.1.13 tnode3

# 노드간 통신 확인
for i in {1..3}; do ping -c 1 tnode$i; done

vagrant destroy -f && rm -rf .vagrant
```

### Ansible 설치 
```sh
python3 --version
Python 3.12.3

# 앤서블 설치
apt install software-properties-common -y
add-apt-repository --yes --update ppa:ansible/ansible
apt install ansible -y

# 중요한 점은 config 파일의 경로로 ansible에 대한 설정을 읽어온다
ansible --version
ansible [core 2.19.5]
  config file = /etc/ansible/ansible.cfg
  configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python3/dist-packages/ansible
  ansible collection location = /root/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/bin/ansible
  python version = 3.12.3 (main, Aug 14 2025, 17:47:21) [GCC 13.3.0] (/usr/bin/python3)
  jinja version = 3.1.2
  pyyaml version = 6.0.1 (with libyaml v0.2.5)

# 앤서블 설정 조회
cat /etc/ansible/ansible.cfg
ansible-config list

mkdir my-ansible
cd my-ansible

# 앤써블이 ssh 접근하기 위한 설정 
tree ~/.ssh
/root/.ssh
└── authorized_keys

# 공개키와 개인키가 생성되었다.
ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
tree ~/.ssh
/root/.ssh/
├── authorized_keys
├── id_rsa
└── id_rsa.pub

# 만일 해당 작업들을 해주지 않는다면 ansible 사용이 불가하다. 
# 앞서 hosts에 정의된 서버를 대상으로 반복 수행한다.
# 공개 키를 관리 노드에 복사 이후 서버명, python 버전 체크 수행 
for i in {1..3}; do sshpass -p 'qwe123' ssh-copy-id -o StrictHostKeyChecking=no root@tnode$i; done
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i cat ~/.ssh/authorized_keys; echo; done
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i hostname; echo; done
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i python3 -V; echo; done
```

### 실습 1 Inventory
인벤토리는 자동화 대상으로 하는 제어 노드(서버)를 지정한다. 포맷은 ini 또는 yaml이다.
```sh
# 인벤토리 생성
cat <<EOT > inventory
10.10.1.11
10.10.1.12
10.10.1.13
EOT

# 인벤토리 정보 출력 
ansible-inventory -i ./inventory --list | jq
  "all": {
    "children": [
      "ungrouped"
    ]
  },
  "ungrouped": {
    "hosts": [
      "10.10.1.11",
      "10.10.1.12",
      "10.10.1.13"
    ]
  }
}

# 
cat /etc/hosts
10.10.1.10 server
10.10.1.11 tnode1
10.10.1.12 tnode2
10.10.1.13 tnode3

# 호스트명 인벤토리 생성 
cat <<EOT > inventory
tnode1
tnode2
tnode3
EOT

# 인벤토리 정보 출력 
ansible-inventory -i ./inventory --list | jq
{
  "_meta": {
    "hostvars": {},
    "profile": "inventory_legacy"
  },
  "all": {
    "children": [
      "ungrouped"
    ]
  },
  "ungrouped": {
    "hosts": [
      "tnode1",
      "tnode2",
      "tnode3"
    ]
  }
}

# 호스트 그룹 설정 예제 
cat /etc/ansible/hosts

# 그룹별 호스트 지정 > inventory/group_inventory 참조
# 여러 그릅별 호스트 지정 > inventory/groups_inventory 참조
# [] 안에 그룹명 작성 후 호스트명 또는 IP 목록 작성

# 중첩 그룹 > inventory/nest_inventory 참조
# 호스트 그룹에 정의한 호스트 그룹을 포함할수도 잇다.
# web 및 db를 포함하는 datacenter 그룹 생성

# 범위를 이용한 호스트 사양 간소화
# 숫자 또는 영문자로 범위 지정
[stard:end]


# inventory 그룹 구성
cat <<EOT > inventory
[web]
tnode1
tnode2

[db]
tnode3

[all:children]
web
db
EOT

# inventory 검증
ansible-inventory -i ./inventory --list | jq
{
  "_meta": {
    "hostvars": {},
    "profile": "inventory_legacy"
  },
  "all": {
    "children": [
      "ungrouped",
      "web",
      "db"
    ]
  },
  "db": {
    "hosts": [
      "tnode3"
    ]
  },
  "web": {
    "hosts": [
      "tnode1",
      "tnode2"
    ]
  }
}

ansible-inventory -i ./inventory --graph
@all:
  |--@ungrouped:
  |--@web:
  |  |--tnode1
  |  |--tnode2
  |--@db:
  |  |--tnode3

# ansible.cfg 파일 생성
# -i를 지정하지 않더라도 기본 인벤토리를 입력한다
cat <<EOT > ansible.cfg
[defaults]
inventory = ./inventory
EOT

# inventory 목록 확인
ansible-inventory --list | jq

# 모든 설정 조회
tree ~/.ansible
ansible-config dump
ansible-config list

# 설정 우선 순위
1. ANSIBLE_CONFIG
  - echo $ANSIBLE_CONFIG
2. ansible.cfg
  - cat $PWD/ansible.cfg
3. ~/.ansible.cfg
  - ls ~/.ansible.cfg
4. /etc/ansible/ansible.
  - cat /etc/ansible/ansible.cfg
```

### 실습 2 Ad-hoc, PlayBook

플레이북을 위한 ansible 환경 설정
```sh
cat <<EOT > ansible.cfg
[defaults]
# 인텐토리 파일 기본 경로
inventory = ./inventory
# SSH 접속 시 사용자
remote_user = root
# SSH 암호 묻는 메시지 표시 여부, key로 통신하기에 false
ask_pass = false

# 보안으로 인해 호스트 권한 없는 사용자가 권한 상승 후 루트로 작업할 때
[privilege_escalation]
# 권한 상승 활성화 시 사용
become = true
# 권한 상승을 위한 사용자 전환 방식
become_method = sudo
# 전환할 사용자
become_user = root
# 암호 묻는 메시지 표시 여부 
become_ask_pass = false
EOT
```

ad-hoc
```sh
# ping 모듈 사용 웹 그룹의 정상 연결 테스트
ansible -m ping web
[WARNING]: Host 'tnode2' is using the discovered Python interpreter at '/usr/bin/python3.12', but future installation of another Python interpreter could cause a different interpreter to be discovered. See https://docs.ansible.com/ansible-core/2.19/reference_appendices/interpreter_discovery.html for more information.
tnode2 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.12"
    },
    "changed": false,
    "ping": "pong"
}

# 암묵적 파이썬 사용 경고, 명시적 설정 권장한다.
# inventory 그룹 구성
cat <<EOT > inventory
[web]
tnode1 ansible_python_interpreter=/usr/bin/python3
tnode2 ansible_python_interpreter=/usr/bin/python3

[db]
tnode3 ansible_python_interpreter=/usr/bin/python3

[all:children]
web
db
EOT

ansible-inventory  --list | jq
{
  "_meta": {
    "hostvars": {
      "tnode1": {
        "ansible_python_interpreter": "/usr/bin/python3"
      },
      "tnode2": {
        "ansible_python_interpreter": "/usr/bin/python3"
      },
      "tnode3": {
        "ansible_python_interpreter": "/usr/bin/python3"
      }
    },

# 이전과 다르게 경고가 출력되지 않는다.
ansible -m ping web
tnode1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
tnode2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}

ansible -m ping db
tnode3 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}

# 암호 활성화, 이전에 말한바와 같이 입력되는 환경변수가 동작한다.
ansible -m ping --ask-pass web
SSH password:

# root 계정 대신 vagrant 계정으로 실행
# 이전에는 에러를 출력하다가 접속후에는 정상적으로 모듈이 동작한다.
ansible -m ping web -u vagrant
ansible -m ping web -u vagrant --ask-pass

ssh vagrant@10.10.1.11 hostname
ssh vagrant@10.10.1.12 hostname
ssh vagrant@10.10.1.13 hostname

sshpass -p 'qwe123' ssh vagrant@tnode1 hostname
sshpass -p 'qwe123' ssh vagrant@tnode2 hostname
sshpass -p 'qwe123' ssh vagrant@tnode3 hostname
sshpass -p 'qwe123' ssh vagrant@tnode3 -t hostname
exit

ansible -m ping web -u vagrant --ask-pass
ansible -m ping db -u vagrant --ask-pass

# shell 모듈
ansible -m shell -a uptime db
tnode3 | CHANGED | rc=0 >>
 01:13:58 up  1:19,  1 user,  load average: 0.01, 0.01, 0.00

ansible -m shell -a "free -h" web
tnode1 | CHANGED | rc=0 >>
               total        used        free      shared  buff/cache   available
Mem:           1.3Gi       259Mi       450Mi       4.8Mi       706Mi       1.0Gi
Swap:          3.7Gi          0B       3.7Gi
tnode2 | CHANGED | rc=0 >>
               total        used        free      shared  buff/cache   available
Mem:           1.3Gi       254Mi       454Mi       4.8Mi       706Mi       1.0Gi
Swap:          3.7Gi          0B       3.7Gi

ansible -m shell -a "tail -n 3 /etc/passwd" all
tnode1 | CHANGED | rc=0 >>
sshd:x:107:65534::/run/sshd:/usr/sbin/nologin
vagrant:x:1000:1000:vagrant:/home/vagrant:/bin/bash
vboxadd:x:999:1::/var/run/vboxadd:/bin/false
tnode2 | CHANGED | rc=0 >>
sshd:x:107:65534::/run/sshd:/usr/sbin/nologin
vagrant:x:1000:1000:vagrant:/home/vagrant:/bin/bash
vboxadd:x:999:1::/var/run/vboxadd:/bin/false
tnode3 | CHANGED | rc=0 >>
tcpdump:x:72:72::/:/sbin/nologin
vagrant:x:1000:1000::/home/vagrant:/bin/bash
vboxadd:x:991:1::/var/run/vboxadd:/bin/false

# ansible.builtin.setup 모듈을 사용하여 제어 노드에 대한 raw 데이터를 가져온다.
ansible tnode1 -m ansible.builtin.setup | grep -iE 'os_family|ansible_distribution'
        "ansible_distribution": "Ubuntu",
        "ansible_distribution_file_parsed": true,
        "ansible_distribution_file_path": "/etc/os-release",
        "ansible_distribution_file_variety": "Debian",
        "ansible_distribution_major_version": "24",
        "ansible_distribution_release": "noble",
        "ansible_distribution_version": "24.04",
        "ansible_os_family": "Debian",

ansible tnode3 -m ansible.builtin.setup | grep -iE 'os_family|ansible_distribution'
        "ansible_distribution": "Rocky",
        "ansible_distribution_file_parsed": true,
        "ansible_distribution_file_path": "/etc/redhat-release",
        "ansible_distribution_file_variety": "RedHat",
        "ansible_distribution_major_version": "9",
        "ansible_distribution_release": "Blue Onyx",
        "ansible_distribution_version": "9.6",
        "ansible_os_family": "RedHat",
```

Playbook
```sh
# 문법 체크
ansible-playbook --syntax-check first-playbook.yml
ansible-playbook --syntax-check first-playbook-with-error.yml

# 플레이븍 실행
ansible-playbook first-playbook.yml

# 새 터미널
ssh tnode1 tail -f /var/log/syslog

# dry-run
# 에러가 발생한다. 왜냐하면 os라 따라 ssh, sshd 다른 서비스로 실행되기 떄문
ansible-playbook --check restart-service.yml
[ERROR]: Task failed: Module failed: Could not find the requested service ssh: host
Origin: /root/my-ansible/r.yml:4:7

2 - hosts: all
3   tasks:
4     - name: Restart sshd service
        ^ column 7

fatal: [tnode3]: FAILED! => {"changed": false, "msg": "Could not find the requested service ssh: host"}
changed: [tnode2]
changed: [tnode1]

PLAY RECAP
tnode1                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode2                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode3                     : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0   

# os 분기별 처리 플레이북 실행
ansible-playbook restart-service.yml
tnode1                     : ok=2    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
tnode2                     : ok=2    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
tnode3                     : ok=2    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
```

### 실습 3 변수
변수 종류 
- 추가 변수: 외부에서 플레이북 실행 시 파라미터러 전달되는 변수
- 플레이 변수: 플레이북 내에서 선언되는 변수 또는 별도 파일로 분리되는 변수
- 호스트 변수: 특정 호스트에서만 사용하는 변수
- 그룹 변수: 인벤토리 정의된 호스트 그룹에 적용하는 변수
- 작업 변수: 플레이북의 수행 결과를 저장 후 후속 작업에 사용할 때 사용된다.

변수 우선 순위
1. 추가변수
2. 플레이 변수
3. 호스트 변수
4. 그룹 변수

```sh
# 그룹 변수
- create-user.yml
- group_inventory

# 새 터미널 모니터링
watch -d "ssh tnode1 tail -n 3 /etc/passwd"
ansible:x:1001:1001::/home/ansible:/bin/sh

# 실행
ansible-playbook create-user.yml

# 멱등성 확인을 위한 재실행
# 유저가 존재하기에 새로 생성되지 않는다.
ansible-playbook create-user.yml

# tnode1~3에서 ansible 사용자 생성 확인
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i tail -n 1 /etc/passwd; echo; done
>> tnode1 <<
ansible:x:1001:1001::/home/ansible:/bin/sh
>> tnode2 <<
ansible:x:1001:1001::/home/ansible:/bin/sh
>> tnode3 <<
ansible:x:1001:1001::/home/ansible:/bin/bash

for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i ls -l /home; echo; done

# 기존 ansible 유저 삭제 후 멱등성 검증
ssh tnode1 userdel -r ansible
ssh tnode1 tail -n 2 /etc/passwd

# 실행
ansible-playbook create-user.yml
tnode1                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

# ansible 유저가 존재한다.
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i tail -n 1 /etc/passwd; echo; done

# 호스트 변수
- host_inventory
- create-user1.yml

# 새 모니터링
watch -d "ssh tnode3 tail -n 3 /etc/passwd"

# 실행
# ansible1 유저가 생성되엇다
ansible-playbook create-user1.yml
tnode3                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

# 확인
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i tail -n 1 /etc/passwd; echo; done
>> tnode1 <<
ansible:x:1001:1001::/home/ansible:/bin/sh
>> tnode2 <<
ansible:x:1001:1001::/home/ansible:/bin/sh
>> tnode3 <<
ansible1:x:1002:1002::/home/ansible1:/bin/bash


# 플레이 변수
- host_inventory
- create-user2.yml

# 새 터미널 모니터링
watch -d "ssh tnode3 tail -n 3 /etc/passwd"

# 실행
ansible-playbook create-user2.yml
tnode1                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode2                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode3                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0  

# 확인
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i tail -n 1 /etc/passwd; echo; done
>> tnode1 <<
ansible2:x:1002:1002::/home/ansible2:/bin/sh

>> tnode2 <<
ansible2:x:1002:1002::/home/ansible2:/bin/sh

>> tnode3 <<
ansible2:x:1003:1003::/home/ansible2:/bin/bash

echo "user: ansible3" > vars_users.yml
- create-user3.yml

# 새 터미널 모니터링
watch -d "ssh tnode3 tail -n 3 /etc/passwd"

# 실행
ansible-playbook create-user3.yml
tnode1                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode2                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode3                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0  

# 확인
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i tail -n 4 /etc/passwd; echo; done
>> tnode1 <<
ansible3:x:1003:1003::/home/ansible3:/bin/sh

>> tnode2 <<
ansible3:x:1003:1003::/home/ansible3:/bin/sh

>> tnode3 <<
ansible3:x:1004:1004::/home/ansible3:/bin/bash

# 추가 변수
# 새 터미널 모니터링
watch -d "ssh tnode3 tail -n 3 /etc/passwd"

# 실행
ansible-playbook -e user=ansible4 create-user3.yml
tnode1                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode2                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode3                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0  

# 확인
for i in {1..3}; do echo ">> tnode$i <<"; ssh tnode$i tail -n 1 /etc/passwd; echo; done
>> tnode1 <<
ansible4:x:1004:1004::/home/ansible4:/bin/sh

>> tnode2 <<
ansible4:x:1004:1004::/home/ansible4:/bin/sh

>> tnode3 <<
ansible4:x:1005:1005::/home/ansible4:/bin/bash

# 작업 변수
# ansible.builtin.debug 모듈 활용
- create-user4.yml

# 새 터미널 모니터링
watch -d "ssh tnode3 tail -n 3 /etc/passwd"

# ok=3 는 실행된 태스크의 수를 의미한다
# facts 수집, 유저 생성, 작업 변수 출력 이렇게 3가지 태스크로 나눠져잇다.
ansible-playbook -e user=ansible5 create-user4.yml
ASK [Gathering Facts] 
ok: [tnode3]

TASK [Create User ansible5] 
ok: [tnode3]

TASK [ansible.builtin.debug] ***************************************************
ok: [tnode3] => {
    "result": {
        "append": false,
        "changed": false,
        "comment": "",
        "failed": false,
        "group": 1006,
        "home": "/home/ansible5",
        "move_home": false,
        "name": "ansible5",
        "shell": "/bin/bash",
        "state": "present",
        "uid": 1006
    }
}

PLAY RECAP 
tnode3                     : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0  
```

### 실습 4 Facts
컨트롤 노드에서 제어 노드에 대해 자동으로 수집하는 변수(자동 예약 변수)이다.

```sh
# 실행
# 서버에 대한 수많은 정보를 수집한다.
ansible-playbook facts.yml
        "all_ipv4_addresses": [
            "10.10.1.13",
...

# 특정 값(ip) 추출
ansible-playbook facts1.yml
TASK [Gathering Facts] 
ok: [tnode3]

TASK [Print all facts] 
ok: [tnode3] => {
    "msg": "The default IPv4 address of tnode3 is 10.0.2.15\n"
}

# 변수로 사용하는 앤서블 팩트로 ansible_* 방식은 비권장하며, ansible_facts.*를 사용할 것을 권장한다
ansible-playbook facts2.yml
TASK [Print all facts] 
ok: [tnode3] => {
    "msg": "The node's host name is tnode3 and the ip is 10.0.2.15\n"
}

# ansibe.cfg
# 앤서블 설정에서 비활성화 할수 잇다. 따라서 ansible_facts.* 만을 강제한다.
inject_facts_as_vars = false
fatal: [tnode3]: FAILED! => {"msg": "Task failed: Finalization of task args for 'ansible.builtin.debug' failed: Error while resolving value for 'msg': 'ansible_hostname' is undefined"}

# 팩트 수집 끄기
# 팩트를 수집하지 않고, 팩트 변수 사용하여 에러 발생
ansible-playbook facts3.yml
[ERROR]: Task failed: Finalization of task args for 'ansible.builtin.debug' failed: Error while resolving value for 'msg': object of type 'dict' has no attribute 'hostname'

# 이전과 다르게 오류가 발생하지 않는다.
ansible-playbook facts3-2.yml
TASK [Print message] 
ok: [tnode3] => {
    "msg": "Hello Ansible World"
}

# ansible.builtin.setup 모듈 활용 수동으로 facts 수집
ansible-playbook facts4.yml
TASK [Manually gather facts] 
ok: [tnode3]

TASK [Print all facts] 
ok: [tnode3] => {
    "msg": "The default IPv4 address of tnode3 is 10.0.2.15\n"
}

# facts 와 인벤토리 정보는 메모리 플러그 사용
# 캐싱하여 파일 또는 DB에 영구 저장가능

# ansible.cfg
[defaults]
inventory = ./inventory
remote_user = root
ask_pass = false
gathering = smart
fact_caching = jsonfile
fact_caching_connection = myfacts

# 사용자 지정 팩트
mkdir /etc/ansible/facts.d

cat <<EOT > /etc/ansible/facts.d/my-custom.fact
[packages]
web_package = httpd
db_package = mariadb-server

[users]
user1 = ansible
user2 = gasida
EOT

ansible-playbook facts5.yml
TASK [Print all facts] 
ok: [localhost] => {
    "ansible_local": {
        "my-custom": {
            "packages": {
                "db_package": "mariadb-server",
                "web_package": "httpd"
            },
            "users": {
                "user1": "ansible",
                "user2": "gasida"
            }
        }
    }
}
```

### 실습 5 반복문
```sh
# 단순 반복문 
- check-services.yml

ansible -m shell -a "pstree |grep sshd" all
ansible -m shell -a "pstree |grep rsyslog" all

# systemd로 실행 중인 서비스 목록을 확인
systemctl list-units --type=service

# 실행
ansible-playbook check-services.yml
tnode1                     : ok=3    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
tnode2                     : ok=3    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
tnode3                     : ok=3    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   

# 실행
ansible-playbook check-services1.yml
ok: [tnode3] => (item=vboxadd-service)
ok: [tnode1] => (item=vboxadd-service)
ok: [tnode2] => (item=vboxadd-service)
ok: [tnode3] => (item=rsyslog)
ok: [tnode1] => (item=rsyslog)
ok: [tnode2] => (item=rsyslog)

# 실행
ansible-playbook check-services2.yml
TASK [Check sshd and rsyslog state] 
ok: [tnode3] => (item=vboxadd-service)
ok: [tnode2] => (item=vboxadd-service)
ok: [tnode1] => (item=vboxadd-service)
ok: [tnode3] => (item=rsyslog)
ok: [tnode2] => (item=rsyslog)
ok: [tnode1] => (item=rsyslog)

PLAY RECAP 
tnode1                     : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode2                     : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode3                     : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0  

# 사전 목록에 의한 반복분, 키 형태로 사용
# ansible.builtin.file 모듈

# 새 터미널 모니터링
watch -d "ssh tnode1 ls -l /var/log/test*.log"

# 실행
ansible-playbook make-file.yml
changed: [tnode1] => (item={'log-path': '/var/log/test1.log', 'log-mode': '0644'})
changed: [tnode2] => (item={'log-path': '/var/log/test1.log', 'log-mode': '0644'})
changed: [tnode3] => (item={'log-path': '/var/log/test1.log', 'log-mode': '0644'})
changed: [tnode1] => (item={'log-path': '/var/log/test2.log', 'log-mode': '0600'})
changed: [tnode2] => (item={'log-path': '/var/log/test2.log', 'log-mode': '0600'})
changed: [tnode3] => (item={'log-path': '/var/log/test2.log', 'log-mode': '0600'})

PLAY RECAP 
tnode1                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode2                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode3                     : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

# 반복문과 Register 변수 사용
# ansible.builtin.shell 모듈 
ansible-playbook loop_register.yml
                "stdout": "I can speak Korean",
                "stdout": "I can speak English",
            
# 실행 
ansible-playbook loop_register1.yml
ok: [localhost] => (item={'changed': True, 'stdout': 'I can speak Korean', 'stderr': '', 'rc': 0, 'cmd': "echo 'I can speak Korean'", 'start': '2026-01-17 02:36:27.494999', 'end': '2026-01-17 02:36:27.496162', 'delta': '0:00:00.001163', 'msg': '', 'invocation': {'module_args': {'_raw_params': "echo 'I can speak Korean'", '_uses_shell': True, 'expand_argument_vars': True, 'stdin_add_newline': True, 'strip_empty_ends': True, 'cmd': None, 'argv': None, 'chdir': None, 'executable': None, 'creates': None, 'removes': None, 'stdin': None}}, 'stdout_lines': ['I can speak Korean'], 'stderr_lines': [], 'failed': False, 'item': 'Korean', 'ansible_loop_var': 'item'}) => {
    "msg": "Stdout: I can speak Korean"
}
ok: [localhost] => (item={'changed': True, 'stdout': 'I can speak English', 'stderr': '', 'rc': 0, 'cmd': "echo 'I can speak English'", 'start': '2026-01-17 02:36:27.618997', 'end': '2026-01-17 02:36:27.620076', 'delta': '0:00:00.001079', 'msg': '', 'invocation': {'module_args': {'_raw_params': "echo 'I can speak English'", '_uses_shell': True, 'expand_argument_vars': True, 'stdin_add_newline': True, 'strip_empty_ends': True, 'cmd': None, 'argv': None, 'chdir': None, 'executable': None, 'creates': None, 'removes': None, 'stdin': None}}, 'stdout_lines': ['I can speak English'], 'stderr_lines': [], 'failed': False, 'item': 'English', 'ansible_loop_var': 'item'}) => {
    "msg": "Stdout: I can speak English"
}
```

### 실습 6 조건문
```sh
# 실행
ansible-playbook when_task.yml
ok: [localhost] => {
    "result": {
        "changed": true,
        "cmd": "echo test",
        "delta": "0:00:00.001203",
        "end": "2026-01-17 02:38:05.192233",
        "failed": false,
        "msg": "",
        "rc": 0,
        "start": "2026-01-17 02:38:05.191030",
        "stderr": "",
        "stderr_lines": [],
        "stdout": "test",
        "stdout_lines": [
            "test"
        ]
    }
}

# 실행
# false 변경 
ansible-playbook when_task.yml
ok: [localhost] => {
    "result": {
        "changed": false,
        "false_condition": "run_my_task",
        "skip_reason": "Conditional result was False",
        "skipped": true
    }
}

# 실행
# os 종류에 따른 다른 태스트 수행
ansible-playbook check-os.yml
TASK [Print supported os] ******************************************************
ok: [tnode1] => {
    "msg": "This Ubuntu need to use apt"
}
skipping: [tnode3]
ok: [tnode2] => {
    "msg": "This Ubuntu need to use apt"
}

PLAY RECAP *********************************************************************
tnode1                     : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode2                     : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
tnode3                     : ok=1    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0 

# 복수 조건문 
# os 종류에 따른 다른 태스트 수행

# 실행
ansible-playbook check-os1.yml
ok: [tnode1] => {
    "msg": "OS Type Ubuntu"
}
ok: [tnode2] => {
    "msg": "OS Type Ubuntu"
}

# 실행
ansible-playbook check-os2.yml
ok: [tnode1] => {
    "msg": "OS Type: Ubuntu OS Version: 24.04"
}
skipping: [tnode3]
ok: [tnode2] => {
    "msg": "OS Type: Ubuntu OS Version: 24.04"
}

# 실행
ansible-playbook check-os3.yml
TASK [Print os type]
ok: [tnode1] => {
    "msg": "OS Type: Ubuntu OS Version: 24.04"
}
skipping: [tnode3]
ok: [tnode2] => {
    "msg": "OS Type: Ubuntu OS Version: 24.04"
}

# 실행
ansible-playbook check-os4.yml
TASK [Print os type]
ok: [tnode1] => {
    "msg": "OS Type: Ubuntu OS Version: 24.04"
}
ok: [tnode2] => {
    "msg": "OS Type: Ubuntu OS Version: 24.04"
}
ok: [tnode3] => {
    "msg": "OS Type: Rocky OS Version: 9.6"
}

# 반복문과 조건문 함께 사용
# ansible.builtin.command 모듈 사용

# 실행
ansible-playbook check-mount.yml --flush-cache
ok: [tnode3] => (item={'mount': '/', 'device': '/dev/sda3', 'fstype': 'xfs', 'options': 'rw,seclabel,relatime,attr2,inode64,logbufs=8,logbsize=32k,noquota', 'dump': 0, 'passno': 0, 'size_total': 63928532992, 'size_available': 61811331072, 'block_size': 4096, 'block_total': 15607552, 'block_available': 15090657, 'block_used': 516895, 'inode_total': 31247872, 'inode_available': 31209703, 'inode_used': 38169, 'uuid': '858fc44c-7093-420e-8ecd-aad817736634'}) => {
    "msg": "Directory / size is 61811331072"
}
skipping: [tnode3] => (item={'mount': '/boot/efi', 'device': '/dev/sda1', 'fstype': 'vfat', 'options': 'rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=ascii,shortname=winnt,errors=remount-ro', 'dump': 0, 'passno': 0, 'size_total': 627875840, 'size_available': 620228608, 'block_size': 4096, 'block_total': 153290, 'block_available': 151423, 'block_used': 1867, 'inode_total': 0, 'inode_available': 0, 'inode_used': 0, 'uuid': '19AA-5BCD'}) 

# 실행
ansible-playbook register-when.yml
TASK [Print rsyslog status] 
ok: [tnode1] => {
    "msg": "Rsyslog status is active"
}
ok: [tnode2] => {
    "msg": "Rsyslog status is active"
}
ok: [tnode3] => {
    "msg": "Rsyslog status is active"
}
```

### 실습 7 핸들러 및 작업 실패 처리 
```sh
# 실행
ansible-playbook handler-sample.yml
TASK [restart rsyslog] 
changed: [tnode2]

RUNNING HANDLER [print msg] 
ok: [tnode2] => {
    "msg": "rsyslog is restarted"
}

# 실행
ansible-playbook ignore-example-1.yml
TASK [Install apache3] 
[ERROR]: Task failed: Module failed: No package matching 'apache3' is available
Origin: /root/my-ansible/r.yml:5:7
3
4   tasks:
5     - name: Install apache3
        ^ column 7
fatal: [tnode1]: FAILED! => {"changed": false, "msg": "No package matching 'apache3' is available"}
PLAY RECAP 
tnode1                     : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0   

# 실행
ansible-playbook ignore-example-2.yml
TASK [Install apache3] 
[ERROR]: Task failed: Module failed: No package matching 'apache3' is available
Origin: /root/my-ansible/r.yml:5:7
3
4   tasks:
5     - name: Install apache3
        ^ column 7
fatal: [tnode1]: FAILED! => {"changed": false, "msg": "No package matching 'apache3' is available"}
...ignoring
TASK [Print msg] 
ok: [tnode1] => {
    "msg": "Before task is ignored"
}


# 실행
ansible-playbook force-handler-1.yml
TASK [install apache3] 
[ERROR]: Task failed: Module failed: No package matching 'apache3' is available
Origin: /root/my-ansible/r.yml:12:7

10         - print msg
11
12     - name: install apache3
         ^ column 7

fatal: [tnode2]: FAILED! => {"changed": false, "msg": "No package matching 'apache3' is available"}

PLAY RECAP 
tnode2                     : ok=2    changed=1    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0   


# 실행 
ansible-playbook force-handler-2.yml
TASK [install apache3] 
[ERROR]: Task failed: Module failed: No package matching 'apache3' is available
Origin: /root/my-ansible/r.yml:13:7

11         - print msg
12
13     - name: install apache3
         ^ column 7

fatal: [tnode2]: FAILED! => {"changed": false, "msg": "No package matching 'apache3' is available"}

RUNNING HANDLER [print msg] 
ok: [tnode2] => {
    "msg": "rsyslog is restarted"
}

PLAY RECAP 
tnode2                     : ok=3    changed=1    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0   

# ansible.builtin.fail 모듈
# 쉘 스크립트는 항상 성공으로 간주하기에 모듈 사용 권징
ansible -m copy -a 'src=/root/my-ansible/adduser-script.sh dest=/root/adduser-script.sh' tnode1

ssh tnode1 ls -l /root
-rw-r--r-- 1 root root 478 Jan 17 03:00 adduser-script.sh

ssh tnode1
chmod +x adduser-script.sh
./adduser-script.sh
exit

# 실행
ansible-playbook failed-when-1.yml

# 실행
ansible-playbook failed-when-2.yml

# 추가 X
ansible -m shell -a "tail -n 3 /etc/passwd" tnode1

# 실행
ansible-playbook failed-when-custom.yml

# ansible.builtin.find 모듈

# 실행
ansible-playbook block-example.yml
TASK [Find Directory]
[WARNING]: Skipped '/var/log/daily_log' path due to this access issue: '/var/log/daily_log' is not a directory
[ERROR]: Task failed: Action failed: Not all paths examined, check warnings for details
Origin: /root/my-ansible/r.yml:10:11

 8     - name: Configure Log Env
 9       block:
10         - name: Find Directory
             ^ column 11

fatal: [tnode2]: FAILED! => {"changed": false, "examined": 0, "failed_when_result": true, "files": [], "matched": 0, "msg": "Not all paths examined, check warnings for details", "skipped_paths": {"/var/log/daily_log": "'/var/log/daily_log' is not a directory"}}


ansible -m shell -a "ls -l /var/log/daily_log/" tnode2
tnode2 | CHANGED | rc=0 >>
total 0
-rw-r--r-- 1 root root 0 Jan 17 03:12 todays.log

# 재실행
ansible-playbook block-example.yml
TASK [Create File] 
changed: [tnode2]

PLAY RECAP 
tnode2                     : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 

# 재실행
ansible -m shell -a "ls -l /var/log/daily_log/" tnode2
tnode2 | CHANGED | rc=0 >>
total 0
-rw-r--r-- 1 root root 0 Jan 17 03:13 todays.log
```

### 실습 8 롤
```sh
# role 생성
ansible-galaxy role init my-role

tree ./my-role/ 
./my-role/
├── defaults
│   └── main.yml
├── files
├── handlers
│   └── main.yml
├── meta
│   └── main.yml
├── README.md
├── tasks
│   └── main.yml
├── templates
├── tests
│   ├── inventory
│   └── test.yml
└── vars
    └── main.yml

# 실행
ansible-playbook role-example.yml
TASK [Print start play] 
ok: [tnode1] => {
    "msg": "Let's start role play"
}

TASK [my-role : install service Apache Web Server] 
ok: [tnode1] => (item=apache2)
changed: [tnode1] => (item=apache2-doc)

TASK [my-role : copy conf file] 
changed: [tnode1]

RUNNING HANDLER [my-role : restart service] 
changed: [tnode1]

PLAY RECAP 
tnode1                     : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

# test
curl tnode1
Hello! Ansible

# 실행
ansible-playbook special_role.yml
TASK [Gathering Facts] 
ok: [tnode1]

TASK [Print start play] 
ok: [tnode1] => {
    "msg": "Let's start role play"
}

TASK [my-role : install service Httpd] 
ok: [tnode1] => (item=apache2)
ok: [tnode1] => (item=apache2-doc)

TASK [my-role : copy conf file] 
ok: [tnode1]

PLAY RECAP 
tnode1                     : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

# test
curl tnode1
Hello! Ansible

# 실행 
# 정적파일 변경
echo "Hello! CloudNet@" > my-role/files/index.html
ansible-playbook role-example.yml

# test
curl tnode1
Hello! CloudNet@


# roles 세견 활용
ssh tnode1

# 방화벽 설치
apt install firewalld -y
systemctl status firewalld

firewall-cmd --list-all
...
  services: dhcpv6-client ssh

# 8080 포트 개방
firewall-cmd --permanent --zone=public --add-port=8080/tcp

# 룰 적용
firewall-cmd --list-all
firewall-cmd --reload

firewall-cmd --list-all
  ports: 8080/tcp

curl localhost
exit

ping -c 1 tnode1
curl tnode1

# 롤생성
ansible-galaxy role init my-role2

# dry-run
ansible-playbook --check role-example2.yml

# 실행
ansible-playbook role-example2.yml
TASK [my-role2 : Config firewalld] 
changed: [tnode1] => (item=http)
changed: [tnode1] => (item=https)
TASK [my-role2 : Reload firewalld] 
changed: [tnode1]

# test
curl tnode1

# 실행v
ansible -m shell -a "firewall-cmd --list-all" tnode1
tnode1 | CHANGED | rc=0 >>
public (default, active)
  target: default
  ingress-priority: 0
  egress-priority: 0
  icmp-block-inversion: no
  interfaces: 
  sources: 
  services: dhcpv6-client ssh
  ports: 8080/tcp
  protocols: 
  forward: yes
  masquerade: no
  forward-ports: 
  source-ports: 
  icmp-blocks: 
  rich rules: 

# 실행
ansible-playbook role-example3.yml
TASK [my-role2 : Config firewalld] 
changed: [tnode1] => (item=http)
changed: [tnode1] => (item=https)
TASK [my-role2 : Reload firewalld] 
changed: [tnode1]

# test
curl tnode1
Hello! CloudNet@


# 실행
# 정의한 바와 같이 순차적으로 동작한다/
ansible-playbook special_role.yml 

PLAY [tnode1] 

TASK [Gathering Facts] 
ok: [tnode1]

TASK [Print Start role] 
ok: [tnode1] => {
    "msg": "Let's start role play"
}

TASK [my-role : install service Apache Web Server] 
ok: [tnode1] => (item=apache2)
ok: [tnode1] => (item=apache2-doc)

TASK [my-role : copy conf file] 
ok: [tnode1]

TASK [my-role2 : Config firewalld] 
ok: [tnode1] => (item=http)
ok: [tnode1] => (item=https)

changed: [tnode1]

TASK [Curl test] 
changed: [tnode1]

RUNNING HANDLER [Print result] 
ok: [tnode1] => {
    "msg": "Hello! CloudNet@\n"
}

TASK [Print Finish role] 
ok: [tnode1] => {
    "msg": "Finish role play"
}

PLAY RECAP 
tnode1                     : ok=9    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

# 방화벽 삭제 
ansible -m shell -a "systemctl stop firewalld" tnode1
ansible -m shell -a "apt remove firewalld -y" tnode1
```
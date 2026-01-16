# 사용자 추가하는 스크립트 파일 내용 확인
wget https://raw.githubusercontent.com/naleeJang/Easy-Ansible/refs/heads/main/chapter_07.3/adduser-script.sh
chmod +x adduser-script.sh
ls -l adduser-script.sh

# 해당 스크립트로 user1 생성해보기
## "passwd: unrecognized option '--stdin'" 에러는 암호 적용 부분에서 발생
./adduser-script.sh
./adduser-script.sh "user1" "qwe123"
tail -n 3 /etc/passwd
sudo userdel -rf user1
tail -n 3 /etc/passwd
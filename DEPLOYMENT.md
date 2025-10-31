# 배포 가이드 (Deployment Guide)

## 서버 정보
- SSH 주소: 65.108.247.150
- 마스토돈 서버: https://fortunaefons.masto.host/
- 기존 봇: @Store (상점), @professor (교수)

## 사전 준비사항

### 1. 서버 접속
```bash
ssh username@65.108.247.150
```

### 2. Ruby 설치 확인
```bash
ruby -v
# Ruby 3.0 이상이어야 함
```

Ruby가 없거나 버전이 낮으면:
```bash
# rbenv 설치 (권장)
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# ruby-build 설치
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# Ruby 3.0.2 설치
rbenv install 3.0.2
rbenv global 3.0.2
```

### 3. Git 설치 확인
```bash
git --version
```

없으면 설치:
```bash
sudo apt update
sudo apt install git -y
```

## 배포 과정

### 1. 프로젝트 업로드

#### 방법 A: Git 사용 (권장)
```bash
# 서버에서
cd ~
git clone [your-repo-url] battle_bot
cd battle_bot
```

#### 방법 B: 직접 업로드
```bash
# 로컬에서
scp -r /path/to/FULL_CODE username@65.108.247.150:~/battle_bot
```

### 2. 의존성 설치
```bash
cd ~/battle_bot
bundle install
```

만약 bundler가 없다면:
```bash
gem install bundler
bundle install
```

### 3. 환경변수 설정
```bash
# .env 파일 생성
nano .env
```

다음 내용 입력:
```env
MASTODON_BASE_URL=https://fortunaefons.masto.host
MASTODON_TOKEN=실제_봇_토큰
GOOGLE_SHEET_ID=실제_시트_ID
GOOGLE_CREDENTIALS_PATH=credentials.json
TZ=Asia/Seoul
```

저장: `Ctrl+O`, `Enter`, 종료: `Ctrl+X`

### 4. Google 인증 파일 업로드
```bash
# 로컬에서
scp /path/to/credentials.json username@65.108.247.150:~/battle_bot/
```

### 5. 테스트 실행
```bash
cd ~/battle_bot
ruby main.rb
```

정상 작동 확인 후 `Ctrl+C`로 종료

## 백그라운드 실행

### 방법 1: Screen 사용 (간단)
```bash
# screen 설치
sudo apt install screen -y

# 새 screen 세션 시작
screen -S battle_bot

# 봇 실행
cd ~/battle_bot
ruby main.rb

# Detach: Ctrl+A, D
# 다시 연결: screen -r battle_bot
```

### 방법 2: Systemd 서비스 (권장)
```bash
# 서비스 파일 생성
sudo nano /etc/systemd/system/battle_bot.service
```

다음 내용 입력:
```ini
[Unit]
Description=Battle Bot for Mastodon
After=network.target

[Service]
Type=simple
User=your_username
WorkingDirectory=/home/your_username/battle_bot
ExecStart=/home/your_username/.rbenv/shims/ruby main.rb
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

서비스 시작:
```bash
# 서비스 활성화
sudo systemctl enable battle_bot

# 서비스 시작
sudo systemctl start battle_bot

# 상태 확인
sudo systemctl status battle_bot

# 로그 확인
sudo journalctl -u battle_bot -f
```

서비스 관리:
```bash
# 재시작
sudo systemctl restart battle_bot

# 정지
sudo systemctl stop battle_bot

# 로그 보기
sudo journalctl -u battle_bot --since today
```

### 방법 3: PM2 사용
```bash
# Node.js 및 PM2 설치
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install node
npm install -g pm2

# 봇 시작
cd ~/battle_bot
pm2 start main.rb --name battle_bot --interpreter ruby

# 자동 시작 설정
pm2 startup
pm2 save

# 관리 명령어
pm2 status          # 상태 확인
pm2 logs battle_bot # 로그 보기
pm2 restart battle_bot # 재시작
pm2 stop battle_bot    # 정지
```

## 마스토돈 봇 계정 설정

### 1. 봇 계정 생성
1. https://fortunaefons.masto.host/ 접속
2. 새 계정 가입 (예: @BattleBot)

### 2. 개발자 애플리케이션 생성
1. 설정 > 개발 > 새 애플리케이션
2. 애플리케이션 이름: Battle Bot
3. 권한 설정:
   - read:accounts
   - read:notifications
   - read:statuses
   - write:statuses
4. 저장 후 액세스 토큰 복사

### 3. 봇 계정 권장 설정
- 프로필에 "봇" 표시 활성화
- 자동 팔로우 비활성화
- 알림 설정 조정

## Google Sheets 설정

### 1. 서비스 계정 생성
1. https://console.cloud.google.com/ 접속
2. 새 프로젝트 생성 또는 기존 프로젝트 선택
3. API 및 서비스 > 사용자 인증 정보
4. 사용자 인증 정보 만들기 > 서비스 계정
5. 서비스 계정 생성 후 키 생성 (JSON)
6. JSON 파일 다운로드

### 2. Google Sheets API 활성화
1. API 및 서비스 > 라이브러리
2. "Google Sheets API" 검색
3. 활성화

### 3. 스프레드시트 권한 설정
1. Google Sheets에서 새 스프레드시트 생성
2. "사용자", "조사" 시트 생성
3. 공유 > 서비스 계정 이메일 추가 (편집자 권한)

## 모니터링

### 로그 확인
```bash
# Screen 사용 시
screen -r battle_bot

# Systemd 사용 시
sudo journalctl -u battle_bot -f

# PM2 사용 시
pm2 logs battle_bot
```

### 시스템 리소스 확인
```bash
# CPU/메모리 사용량
top
htop  # 더 보기 좋음 (설치: sudo apt install htop)

# 디스크 사용량
df -h
```

## 업데이트

### 코드 업데이트
```bash
cd ~/battle_bot

# 백업
cp -r ~/battle_bot ~/battle_bot_backup_$(date +%Y%m%d)

# Git 사용 시
git pull

# 수동 업로드 시
# 로컬에서: scp -r /path/to/updated/files username@65.108.247.150:~/battle_bot/

# 의존성 업데이트
bundle install

# 재시작 (방법에 따라)
sudo systemctl restart battle_bot  # Systemd
pm2 restart battle_bot             # PM2
# Screen: 세션에 들어가서 Ctrl+C 후 다시 실행
```

## 문제 해결

### 봇이 응답하지 않는 경우
1. 프로세스 확인
```bash
ps aux | grep ruby
```

2. 로그 확인
```bash
sudo journalctl -u battle_bot --since "10 minutes ago"
```

3. 네트워크 연결 확인
```bash
curl https://fortunaefons.masto.host/api/v1/instance
```

### 메모리 부족
```bash
# 스왑 파일 생성
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Google Sheets 연결 오류
1. credentials.json 위치 확인
2. 서비스 계정 권한 확인
3. API 할당량 확인

## 보안 권장사항

### 1. 방화벽 설정
```bash
# ufw 설치 및 활성화
sudo apt install ufw
sudo ufw allow ssh
sudo ufw enable
```

### 2. SSH 키 인증 사용
```bash
# 로컬에서 키 생성
ssh-keygen -t rsa -b 4096

# 공개키 복사
ssh-copy-id username@65.108.247.150
```

### 3. 정기 업데이트
```bash
# 시스템 업데이트
sudo apt update && sudo apt upgrade -y

# Ruby 의존성 업데이트
bundle update
```

### 4. 환경변수 보호
```bash
chmod 600 ~/battle_bot/.env
chmod 600 ~/battle_bot/credentials.json
```

## 백업 전략

### 자동 백업 스크립트
```bash
# backup.sh 생성
nano ~/backup.sh
```

내용:
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=~/battle_bot_backups
mkdir -p $BACKUP_DIR

# 코드 백업
cp -r ~/battle_bot $BACKUP_DIR/battle_bot_$DATE

# 7일 이상 된 백업 삭제
find $BACKUP_DIR -type d -mtime +7 -exec rm -rf {} +

echo "Backup completed: $DATE"
```

실행 권한 부여:
```bash
chmod +x ~/backup.sh
```

Cron 등록 (매일 새벽 3시):
```bash
crontab -e
# 다음 줄 추가
0 3 * * * /home/username/backup.sh >> /home/username/backup.log 2>&1
```

## 다중 봇 운영

같은 서버에서 여러 봇 실행:
```bash
# 각 봇마다 별도 디렉토리
~/battle_bot/
~/store_bot/
~/professor_bot/

# 각각 별도 서비스로 등록
sudo systemctl start battle_bot
sudo systemctl start store_bot
sudo systemctl start professor_bot
```

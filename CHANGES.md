# 변경사항 (CHANGES)

## 범용화 작업

### 1. 서버 정보 범용화
기존의 하드코딩된 서버 정보를 환경변수로 전환하여 다른 마스토돈 서버에서도 사용 가능하도록 수정했습니다.

**변경된 파일:**
- `.env` - 서버 URL과 토큰을 환경변수로 관리
- `main.rb` - 환경변수에서 서버 정보 로드
- `mastodon_client.rb` - 범용 마스토돈 클라이언트

**사용법:**
```env
MASTODON_BASE_URL=https://your-server.com
MASTODON_TOKEN=your_token_here
```

### 2. 총괄계 기능 추가
`@FortunaeFons` 총괄계 계정이 모든 전투와 조사 알림을 받도록 설정했습니다.

**변경된 파일:**
- `core/battle_engine.rb` - 전투 알림 시 총괄계 멘션 추가
- `commands/investigate_command.rb` - 조사 결과 시 총괄계 멘션

**동작 방식:**
- 모든 공개 전투 메시지에 `@FortunaeFons` 멘션
- 총괄계는 DM을 받지 않음 (참가자만 DM 수신)

### 3. 교수봇 스케줄 변경
기존의 교수봇 알림 시간을 수정했습니다.

**변경 내역:**
- 아침 출석 안내: 09:00 → 07:00
- 출석 마감: 12:00 → 10:00
- 새벽 통금 알림: 00:00 → 02:00
- 통금 해제: 06:00 (유지)

**변경된 파일:**
- `cron_tasks/morning_attendance_push.rb`
- `cron_tasks/evening_attendance_end.rb`
- `cron_tasks/curfew_alert.rb`

### 4. 조사 제한 제거
하루 1회 조사 제한을 제거하여 무제한 조사가 가능하도록 변경했습니다.

**변경된 파일:**
- `commands/investigate_command.rb` - 날짜 확인 로직 제거

**변경 사항:**
- 기존: `마지막조사일` 필드 확인 후 하루 1회 제한
- 변경: 제한 없이 자유롭게 조사 가능
- `마지막조사일` 필드는 기록용으로만 업데이트

### 5. 구글 시트 호환성
Google Sheets API v4를 사용하여 시트 구조 개선:

**변경된 파일:**
- `sheet_manager.rb` - 새로운 API 사용
- 모든 명령어 파일 - 새 시트 매니저 호환

**장점:**
- 더 빠른 읽기/쓰기
- 안정적인 API
- 더 나은 오류 처리

## 마이그레이션 가이드

### 기존 프로젝트에서 업데이트하는 방법

1. 환경변수 파일 생성
```bash
cp .env.example .env
# .env 파일을 열어서 본인의 서버 정보 입력
```

2. 의존성 재설치
```bash
bundle install
```

3. 구글 시트 구조 확인
- 기존 시트 구조가 그대로 유지됨
- 추가 변경 불필요

4. 총괄계 계정 생성 (선택사항)
- 마스토돈 서버에서 `@FortunaeFons` 계정 생성
- 또는 다른 총괄계 계정명 사용 시 코드 수정

5. 봇 재시작
```bash
ruby main.rb
```

## 호환성

### 지원 환경
- Ruby 3.0 이상
- 모든 마스토돈 서버 (v3.0+)
- Google Sheets API v4

### 테스트된 서버
- https://fortunaefons.masto.host/
- https://eclyria.pics (기존 서버)

## 향후 계획

### 예정된 기능
- 멀티 전투 지원 (동시에 여러 전투 진행)
- 전투 로그 기록 시스템
- 통계 및 랭킹 시스템
- 아이템 거래 시스템

### 개선 사항
- 더 나은 오류 처리
- 성능 최적화
- 코드 문서화 강화

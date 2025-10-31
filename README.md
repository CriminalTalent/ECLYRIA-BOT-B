# Battle Bot - 마스토돈 전투 시스템

마스토돈 기반의 1:1 / 2:2 전투 시스템과 행운 기반 조사 시스템을 제공하는 RP 유틸 봇입니다.

## 주요 기능

### 전투 시스템
- 1:1 전투
- 2:2 팀 전투
- 허수아비 연습 전투 (상/중/하)
- D20 기반 판정 시스템
- 이중 알림 (공개 타임라인 + 참가자 DM)

### 조사 시스템
- 기본 조사
- 정밀조사
- 감지
- 훔쳐보기
- DM 조사 결과 전송

## 설치 방법

### 1. 의존성 설치
```bash
bundle install
```

### 2. 환경변수 설정
`.env` 파일을 생성하고 다음 내용을 입력하세요:

```env
MASTODON_BASE_URL=https://fortunaefons.masto.host
MASTODON_TOKEN=your_token_here
GOOGLE_SHEET_ID=your_sheet_id_here
GOOGLE_CREDENTIALS_PATH=credentials.json
TZ=Asia/Seoul
```

### 3. Google 서비스 계정 설정
1. Google Cloud Console에서 서비스 계정 생성
2. JSON 키를 다운로드하여 `credentials.json`으로 저장
3. Google Sheets의 공유 설정에서 서비스 계정 이메일을 "편집자"로 추가

### 4. 실행
```bash
ruby main.rb
```

## 사용 명령어

### 전투 명령
```
@bot [전투개시/@상대방]                    # 1:1 전투
@bot [전투개시/@우리팀/@상대1/@상대2]      # 2:2 전투
@bot [허수아비 상/중/하]                   # 허수아비 연습
@bot [공격]                                # 공격
@bot [방어]                                # 방어
@bot [반격]                                # 반격
@bot [도주]                                # 도주
@bot [물약사용]                            # 물약 사용
```

### 조사 명령
```
@bot [조사] [대상명]
@bot [정밀조사] [대상명]
@bot [감지] [대상명]
@bot [훔쳐보기] [대상명]
@bot DM조사결과 @유저 결과내용
```

## Google Sheets 구조

### 사용자 시트
| 열 | 필드명 | 설명 |
|----|--------|------|
| A | ID | 마스토돈 계정 |
| B | 이름 | 캐릭터명 |
| C | 체력 | 현재 HP |
| D | 공격력 | 공격 스탯 |
| E | 마력 | 마법 스탯 |
| F | 방어력 | 방어 스탯 |
| G | 민첩 | 민첩 스탯 |
| H | 행운 | 행운 스탯 |
| I | 아이템 | 소지 아이템 |
| J | 마지막조사일 | 조사 날짜 |

### 조사 시트
| 열 | 필드명 | 설명 |
|----|--------|------|
| A | 대상 | 조사 대상명 |
| B | 종류 | 조사/정밀조사/감지/훔쳐보기/DM조사 |
| C | 난이도 | 성공 기준값 |
| D | 성공결과 | 성공 시 메시지 |
| E | 실패결과 | 실패 시 메시지 |

## 프로젝트 구조
```
battle_bot/
├── main.rb                     # 실행 진입점
├── mastodon_client.rb          # 마스토돈 API 래퍼
├── sheet_manager.rb            # Google Sheets 핸들러
├── command_parser.rb           # 명령어 파서
├── commands/                   # 명령어 핸들러
│   ├── battle_command.rb
│   ├── investigate_command.rb
│   ├── potion_command.rb
│   └── dm_investigation_command.rb
├── core/                       # 핵심 시스템
│   ├── battle_engine.rb
│   └── battle_state.rb
├── .env                        # 환경변수
├── credentials.json            # Google API 인증
└── Gemfile                     # Ruby 의존성
```

## 주의사항
1. 한 번에 하나의 전투만 가능
2. 시트 편집 권한 필요
3. API 사용량 제한 고려
4. 정기적인 데이터 백업 권장

## 서버 정보
- SSH: 65.108.247.150
- 마스토돈: https://fortunaefons.masto.host/
- 상점봇: @Store
- 교수봇: @professor

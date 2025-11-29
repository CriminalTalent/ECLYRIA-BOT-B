$stdout.sync = true
$stderr.sync = true

require_relative '/root/http_patch'

# main.rb
require 'dotenv/load'
require 'set'
require 'time'

require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'

# === 시트 설정 ===
SHEET_ID = ENV['GOOGLE_SHEET_ID'] || '1sf6DpuOZXpLVMc8EwJr_gzsUOx_GO2Tp3mgsIQZtkOQ'
CREDENTIALS_PATH = '/root/mastodon_bots/battle_bot/credentials.json'

# === 봇 시작 ===
BOT_START_TIME = Time.now
puts "[전투봇] 실행 시작 (#{BOT_START_TIME.strftime('%H:%M:%S')})"

# === Google Sheets 연결 ===
begin
  sheet_manager = SheetManager.new(SHEET_ID, CREDENTIALS_PATH)
  puts "Google Sheets 연결 성공: battle_bot"
rescue => e
  puts "[Google Sheets 연결 실패] #{e.message}"
  exit
end

# === 마스토돈 클라이언트 ===
mastodon = MastodonClient.new(
  base_url: ENV['MASTODON_BASE_URL'],
  token: ENV['MASTODON_TOKEN']
)

# === 명령어 require ===
require_relative 'commands/investigate_command'
require_relative 'commands/dm_investigation_command'
require_relative 'commands/battle_command'
require_relative 'commands/potion_command'

# === 파서 ===
parser = CommandParser.new(mastodon, sheet_manager)

puts "📅 전투봇 스케줄러 없음 (전투 전용)"
puts "👂 멘션/DM 스트리밍 시작..."

processed = Set.new

# === 재시도 설정 ===
MAX_SSL_RETRY = 3
MAX_GENERAL_RETRY = 3
ssl_error_count = 0
general_retry_count = 0

# ===========================================
# 🔥 스트리밍 루프 — mention + DM 모두 처리
# ===========================================
loop do
  begin
    puts "[마스토돈] user 스트림 구독 시작... (@#{mastodon.bot_username} 멘션만 처리)"
    
    mastodon.stream_user do |status|
      begin
        # 연결 성공 시 카운터 리셋
        ssl_error_count = 0
        general_retry_count = 0
        
        # status는 해시 형태 (symbolize_names: true)
        mention_id = status[:id]
        
        next if processed.include?(mention_id)
        
        # created_at 파싱
        created = Time.parse(status[:created_at])
        next if created < BOT_START_TIME
        
        processed.add(mention_id)
        
        # 발신자 정보
        sender = status[:account][:acct]
        content = status[:content]
        
        puts "[스트리밍] #{mention_id} - @#{sender}"
        
        parser.handle(status)
        
      rescue => e
        puts "[에러] 멘션 처리 오류: #{e.class}: #{e.message}"
        puts e.backtrace.first(5)
      end
    end
    
  rescue EOFError, OpenSSL::SSL::SSLError => e
    # SSL 관련 오류 처리
    ssl_error_count += 1
    puts "[SSL 오류 #{ssl_error_count}/#{MAX_SSL_RETRY}] #{e.message}"
    
    if ssl_error_count >= MAX_SSL_RETRY
      puts "[경고] SSL 오류가 #{MAX_SSL_RETRY}회 연속 발생했습니다."
      puts "[대기] 30초 후 재연결을 시도합니다..."
      sleep 30
      ssl_error_count = 0
    else
      puts "[재시도] 3초 후 재연결..."
      sleep 3
    end
    
    retry
    
  rescue Interrupt
    # Ctrl+C로 종료
    puts "\n[종료] 봇을 종료합니다..."
    break
    
  rescue SystemExit, SignalException
    # 시스템 종료 시그널
    puts "\n[종료] 시스템 종료 시그널 수신..."
    break
    
  rescue => e
    # 기타 모든 오류
    general_retry_count += 1
    puts "[스트리밍 오류 #{general_retry_count}/#{MAX_GENERAL_RETRY}] #{e.class}: #{e.message}"
    puts e.backtrace.first(5)
    
    if general_retry_count >= MAX_GENERAL_RETRY
      puts "[심각] 일반 오류가 #{MAX_GENERAL_RETRY}회 연속 발생했습니다."
      puts "[대기] 60초 후 재연결을 시도합니다..."
      sleep 60
      general_retry_count = 0
    else
      puts "[재시도] 5초 후 재연결..."
      sleep 5
    end
    
    retry
  end
end

puts "[종료] 전투봇이 정상적으로 종료되었습니다."

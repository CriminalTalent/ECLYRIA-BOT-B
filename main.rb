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

# ===========================================
# 🔥 스트리밍 루프 — mention + DM 모두 처리
# ===========================================
loop do
  begin
    mastodon.stream_user do |status|
      begin
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
        
        puts "[처리] #{mention_id} / #{created.strftime('%H:%M:%S')} - @#{sender}"
        puts "[내용] #{content}"
        
        parser.handle(status)
        
      rescue => e
        puts "[에러] 멘션 처리 오류: #{e.class}: #{e.message}"
        puts e.backtrace.first(5)
      end
    end
    
  rescue => e
    puts "[스트리밍 오류] #{e.class}: #{e.message}"
    puts "[3초 후 재접속]"
    sleep 3
    puts "[마스토돈] 멘션 스트리밍 재시작..."
    retry
  end
end

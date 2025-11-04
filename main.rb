$stdout.sync = true
$stderr.sync = true
require_relative '/root/http_patch'

# main.rb
require 'dotenv/load'
require 'set'
require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'

# === 환경 설정 ===
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
  puts "Google Sheets 연결 실패: #{e.message}"
  exit
end

# === 마스토돈 클라이언트 초기화 ===
mastodon = MastodonClient.new(
  base_url: ENV['MASTODON_BASE_URL'],
  token: ENV['MASTODON_TOKEN']
)

# === 명령어 파서 초기화 ===
parser = CommandParser.new(mastodon, sheet_manager)

puts "📅 전투봇 스케줄러 없음 (전투 전용)"

# === 멘션 스트리밍 ===
processed_mentions = Set.new
puts "👂 멘션 스트리밍 시작..."

mastodon.stream_user do |mention|
  begin
    mention_id = mention.id
    next if processed_mentions.include?(mention_id)

    mention_time = Time.parse(mention.status.created_at)
    next if mention_time < BOT_START_TIME

    processed_mentions.add(mention_id)

    sender_full = mention.account.acct
    content = mention.status.content

    puts "[처리] 새 멘션 ID #{mention_id}: #{mention_time.strftime('%H:%M:%S')} - @#{sender_full}"
    puts "[내용] #{content}"

    parser.handle(mention.status)
  rescue => e
    puts "[에러] 처리 중 예외 발생: #{e.message}"
    puts e.backtrace.first(5)
  end
end

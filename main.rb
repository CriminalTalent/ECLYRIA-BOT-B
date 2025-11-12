$stdout.sync = true
$stderr.sync = true
# require_relative '/root/http_patch'
require_relative 'core/battle_engine'

# main.rb
require 'cgi'
require 'ostruct'
require 'time'
require 'dotenv/load'
require 'set'
require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'

last_seen_id = nil

# === 환경 설정 ===
SHEET_ID = ENV['GOOGLE_SHEET_ID'] || '1sf6DpuOZXpLVMc8EwJr_gzsUOx_GO2Tp3mgsIQZtkOQ'
CREDENTIALS_PATH = 'credentials.json'

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
  ENV['MASTODON_BASE_URL'],
  ENV['MASTODON_TOKEN']
)

# === 명령어 파서 초기화 ===
parser = CommandParser.new(mastodon, sheet_manager)

puts "📅 전투봇 스케줄러 없음 (전투 전용)"

# === HTML → 텍스트 유틸 추가 ===
def html_to_text(html)
  return '' if html.nil?
  html = html.gsub(/<br\s*\/?>/i, "\n")
             .gsub(/<\/p>/i, "\n")
             .gsub(/<[^>]+>/, '')
  CGI.unescapeHTML(html).strip
end

# === 멘션 스트리밍 ===
processed_mentions = Set.new
puts "👂 멘션 폴링 시작..."

last_seen_id = nil

loop do
  begin
    notifs = mastodon.notifications(since_id: last_seen_id, limit: 40)
    notifs.sort_by { |n| n['id'].to_i }.each do |n|
      next unless n['type'] == 'mention' && n['status']
    
      mention_id   = n['id']
      status       = n['status']
      created_at   = Time.parse(status['created_at']) rescue Time.now
      next if created_at < BOT_START_TIME
      next if processed_mentions.include?(mention_id)
    
      processed_mentions.add(mention_id)
      sender_full  = n.dig('account', 'acct')            # user_id
      content_html = status['content']
      text         = html_to_text(content_html)          # “[허수아비 하]” 형태로 추출됨
      reply_id     = status['id']                        # 이 상태에 답글 달기
    
      puts "[처리] 새 멘션 ID #{mention_id}: #{created_at.strftime('%H:%M:%S')} - @#{sender_full}"
      puts "[내용] #{content_html}"
    
      parser.parse(text, sender_full, reply_id)
    
      sid = n['id'].to_i
      last_seen_id = sid if last_seen_id.nil? || sid > last_seen_id
    end

  rescue => e
    puts "[에러] 폴링 중 예외: #{e.message}"
  ensure
    sleep 5
  end
end

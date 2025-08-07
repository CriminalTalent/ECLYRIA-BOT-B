# main.rb

require 'mastodon'
require 'google_drive'
require 'dotenv/load'
require_relative './command_parser'
require_relative './core/sheet_manager'

# ─────────────────────────────
# 1. 마스토돈 API 초기화
# ─────────────────────────────
client = Mastodon::REST::Client.new(
  base_url: ENV['MASTODON_BASE_URL'],
  bearer_token: ENV['MASTODON_ACCESS_TOKEN']
)

# ─────────────────────────────
# 2. 구글 시트 연결
# ─────────────────────────────
session = GoogleDrive::Session.from_service_account_key('credentials.json') # 서비스 계정 인증
spreadsheet = session.spreadsheet_by_key(ENV['SPREADSHEET_ID'])

# sheet_manager 초기화
SheetManager.set_sheet(spreadsheet)

# ─────────────────────────────
# 3. 명령어 파서 생성
# ─────────────────────────────
parser = CommandParser.new(client, spreadsheet)

# ─────────────────────────────
# 4. 스트리밍 처리
# ─────────────────────────────
stream = Mastodon::Streaming::Client.new(
  base_url: ENV['MASTODON_BASE_URL'],
  bearer_token: ENV['MASTODON_ACCESS_TOKEN']
)

puts "🤖 봇이 실행되었습니다..."

stream.user do |event|
  case event
  when Mastodon::Streaming::Notification
    next unless event.type == 'mention'
    status = event.status
    user = status.account.acct

    # 자기 자신 메시지 무시
    next if user == client.verify_credentials.acct

    puts "💬 명령 수신 from #{user}: #{status.content.gsub(/<[^>]+>/, '')}"

    # 명령 처리
    parser.handle(status)
  end
end


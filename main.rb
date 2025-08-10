# main.rb
require 'dotenv/load'
require 'google/apis/sheets_v4'
require 'googleauth'
require 'set'  # Set 모듈 추가
require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'

# 봇 시작 시간 기록
BOT_START_TIME = Time.now
puts "[전투봇] 실행 시작 (#{BOT_START_TIME.strftime('%H:%M:%S')})"

# Google Sheets 서비스 초기화
begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: 'https://www.googleapis.com/auth/spreadsheets'
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  spreadsheet = sheets_service.get_spreadsheet(ENV["GOOGLE_SHEET_ID"])
  puts "Google Sheets 연결 성공: #{spreadsheet.properties.title}"
rescue => e
  puts "Google Sheets 연결 실패: #{e.message}"
  exit
end

# 시트 매니저 초기화
sheet_manager = SheetManager.new(sheets_service, ENV["GOOGLE_SHEET_ID"])

# 마스토돈 클라이언트 초기화
mastodon = MastodonClient.new(
  base_url: ENV['MASTODON_BASE_URL'],
  token: ENV['MASTODON_TOKEN']
)

# 명령어 파서 초기화
parser = CommandParser.new(mastodon, sheet_manager)

puts "📅 전투봇 스케줄러 없음 (전투 전용)"

# 처리된 멘션 ID 추적 (중복 방지)
processed_mentions = Set.new

# 멘션 스트리밍 시작
puts "👂 멘션 스트리밍 시작..."
mastodon.stream_user do |mention|
  begin
    # 멘션 ID로 중복 처리 방지
    mention_id = mention.id
    if processed_mentions.include?(mention_id)
      puts "[무시] 이미 처리된 멘션: #{mention_id}"
      next
    end
    
    # 봇 시작 시간 이전의 멘션은 무시
    mention_time = Time.parse(mention.status.created_at)
    if mention_time < BOT_START_TIME
      puts "[무시] 봇 시작 이전 멘션: #{mention_time.strftime('%H:%M:%S')}"
      next
    end

    # 멘션 ID 기록
    processed_mentions.add(mention_id)
    
    sender_full = mention.account.acct
    content = mention.status.content
    
    puts "[처리] 새 멘션 ID #{mention_id}: #{mention_time.strftime('%H:%M:%S')} - @#{sender_full}"
    puts "[내용] #{content}"
    
    # 멘션을 전투 파서로 전달
    parser.handle(mention.status)
  rescue => e
    puts "[에러] 처리 중 예외 발생: #{e.message}"
    puts e.backtrace.first(5)
  end
end

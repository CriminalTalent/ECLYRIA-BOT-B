$stdout.sync = true
$stderr.sync = true

require 'dotenv/load'
require 'set'
require 'time'

require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'

SHEET_ID = ENV['GOOGLE_SHEET_ID']
CREDENTIALS_PATH = ENV['GOOGLE_CREDENTIALS_PATH']

BOT_START_TIME = Time.now
puts "[전투봇] 실행 시작 (#{BOT_START_TIME.strftime('%H:%M:%S')})"

begin
  sheet_manager = SheetManager.new(SHEET_ID, CREDENTIALS_PATH)
  puts "Google Sheets 연결 성공"
rescue => e
  puts "[Google Sheets 연결 실패] #{e.message}"
  exit
end

mastodon = MastodonClient.new(
  base_url: ENV['MASTODON_BASE_URL'],
  token: ENV['MASTODON_TOKEN']
)

parser = CommandParser.new(mastodon, sheet_manager)
puts "[파서] 초기화 완료"

puts "멘션 스트리밍 시작..."

processed = Set.new
MAX_SSL_RETRY = 3
MAX_GENERAL_RETRY = 3
ssl_error_count = 0
general_retry_count = 0

loop do
  begin
    puts "[마스토돈] user 스트림 구독 시작..."
    
    mastodon.stream_user do |status|
      begin
        ssl_error_count = 0
        general_retry_count = 0
        
        mention_id = status[:id]
        next if processed.include?(mention_id)
        
        created = Time.parse(status[:created_at])
        next if created < BOT_START_TIME
        
        processed.add(mention_id)
        
        sender = status[:account][:acct]
        puts "[스트리밍] #{mention_id} - @#{sender}"
        
        parser.handle(status)
        
      rescue => e
        puts "[에러] 멘션 처리 오류: #{e.class}: #{e.message}"
        puts e.backtrace.first(5)
      end
    end
    
  rescue EOFError, OpenSSL::SSL::SSLError => e
    ssl_error_count += 1
    puts "[SSL 오류 #{ssl_error_count}/#{MAX_SSL_RETRY}] #{e.message}"
    
    if ssl_error_count >= MAX_SSL_RETRY
      puts "[재시도] 30초 후 재연결..."
      sleep 30
    else
      puts "[재시도] 3초 후 재연결..."
      sleep 3
    end
    retry
    
  rescue Interrupt
    puts "\n[종료] 봇을 종료합니다..."
    break
    
  rescue SystemExit, SignalException
    puts "\n[종료] 시스템 종료 시그널 수신..."
    break
    
  rescue => e
    general_retry_count += 1
    puts "[스트리밍 오류 #{general_retry_count}/#{MAX_GENERAL_RETRY}] #{e.class}: #{e.message}"
    puts e.backtrace.first(5)
    
    if general_retry_count >= MAX_GENERAL_RETRY
      puts "[재시도] 60초 후 재연결..."
      sleep 60
    else
      puts "[재시도] 5초 후 재연결..."
      sleep 5
    end
    retry
  end
end

puts "[종료] 전투봇이 정상적으로 종료되었습니다."

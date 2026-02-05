# main.rb
$stdout.sync = true
$stderr.sync = true

require 'dotenv/load'
require 'set'
require 'time'
require 'openssl'

require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'
require_relative 'core/battle_engine'

# --------------------
# ENV
# --------------------
SHEET_ID          = ENV['GOOGLE_SHEET_ID']
CREDENTIALS_PATH  = ENV['GOOGLE_CREDENTIALS_PATH']
BOT_START_TIME    = Time.now

if SHEET_ID.to_s.strip.empty? || CREDENTIALS_PATH.to_s.strip.empty?
  puts "[오류] GOOGLE_SHEET_ID / GOOGLE_CREDENTIALS_PATH 환경변수 누락"
  exit 1
end

if ENV['MASTODON_BASE_URL'].to_s.strip.empty? || ENV['MASTODON_TOKEN'].to_s.strip.empty?
  puts "[오류] MASTODON_BASE_URL / MASTODON_TOKEN 환경변수 누락"
  exit 1
end

puts "[전투봇] 실행 시작 (#{BOT_START_TIME.strftime('%H:%M:%S')})"

# --------------------
# Google Sheets
# --------------------
begin
  sheet_manager = SheetManager.new(SHEET_ID, CREDENTIALS_PATH)
  puts "Google Sheets 연결 성공"
rescue => e
  puts "[Google Sheets 연결 실패] #{e.message}"
  exit 1
end

# --------------------
# Mastodon
# --------------------
mastodon = MastodonClient.new(
  base_url: ENV['MASTODON_BASE_URL'],
  token: ENV['MASTODON_TOKEN']
)

battle_engine = BattleEngine.new(mastodon, sheet_manager)
parser = CommandParser.new(mastodon, battle_engine)
puts "[파서] 초기화 완료"

puts "멘션 스트리밍 시작..."

processed = Set.new
MAX_SSL_RETRY = 3
MAX_GENERAL_RETRY = 3
ssl_error_count = 0
general_retry_count = 0

# --------------------
# status 정규화 유틸
# mastodon_client 구현에 따라 이벤트가 Array로 올 수 있음(그때 방어)
# --------------------
def extract_status(obj)
  return obj if obj.is_a?(Hash)

  # 예: [event, payload] 형태로 오는 경우
  if obj.is_a?(Array)
    payload = obj[1]
    return payload if payload.is_a?(Hash)
  end

  nil
end

loop do
  begin
    puts "[마스토돈] user 스트림 구독 시작..."

    mastodon.stream_user do |raw|
      begin
        ssl_error_count = 0
        general_retry_count = 0

        status = extract_status(raw)
        unless status
          puts "[스트리밍] status 형식이 Hash가 아님(스킵): #{raw.class}"
          next
        end

        mention_id = status[:id] || status['id']
        next unless mention_id
        next if processed.include?(mention_id)

        created_at = status[:created_at] || status['created_at']
        if created_at
          created = Time.parse(created_at.to_s) rescue nil
          next if created && created < BOT_START_TIME
        end

        processed.add(mention_id)

        acct = (status.dig(:account, :acct) || status.dig('account', 'acct') || "unknown")
        puts "[스트리밍] #{mention_id} - @#{acct}"

        parser.parse(status)

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

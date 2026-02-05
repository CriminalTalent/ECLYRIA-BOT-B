# main.rb  (교체용 전체 코드)
$stdout.sync = true
$stderr.sync = true

require 'dotenv/load'
require 'set'
require 'time'

require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'
require_relative 'core/battle_engine'

# -------------------------
# Hash 안전 접근 (symbol/string 키 모두 대응)
# -------------------------
def hget(obj, key)
  return nil unless obj.is_a?(Hash)
  obj[key] || obj[key.to_s]
end

# -------------------------
# 스트림 이벤트 -> "status Hash"로 정규화
# - ["update", {...}] 같은 배열이면 payload만 꺼냄
# - Hash면 그대로
# - 아니면 nil
# -------------------------
def normalize_status(raw)
  if raw.is_a?(Array)
    raw = raw[1] || raw.last
  end
  return nil unless raw.is_a?(Hash)
  raw
end

# -------------------------
# ENV
# -------------------------
SHEET_ID         = ENV['GOOGLE_SHEET_ID']
CREDENTIALS_PATH = ENV['GOOGLE_CREDENTIALS_PATH']
BOT_START_TIME   = Time.now

if SHEET_ID.nil? || SHEET_ID.strip.empty? || CREDENTIALS_PATH.nil? || CREDENTIALS_PATH.strip.empty?
  puts "[오류] GOOGLE_SHEET_ID / GOOGLE_CREDENTIALS_PATH 환경변수 누락"
  exit 1
end

base_url = ENV['MASTODON_BASE_URL']
token    = ENV['MASTODON_TOKEN']

if base_url.nil? || base_url.strip.empty? || token.nil? || token.strip.empty?
  puts "[오류] MASTODON_BASE_URL / MASTODON_TOKEN 환경변수 누락"
  exit 1
end

# URL 형식 보정 (not an HTTP URI 방지)
base_url = base_url.strip
base_url = "https://#{base_url}" unless base_url.start_with?('http://', 'https://')

puts "[전투봇] 실행 시작 (#{BOT_START_TIME.strftime('%H:%M:%S')})"

# -------------------------
# Google Sheets
# -------------------------
begin
  sheet_manager = SheetManager.new(SHEET_ID, CREDENTIALS_PATH)
  puts "Google Sheets 연결 성공"
rescue => e
  puts "[Google Sheets 연결 실패] #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

# -------------------------
# Mastodon
# -------------------------
mastodon = MastodonClient.new(
  base_url: base_url,
  token: token
)

begin
  me = mastodon.verify_credentials
  puts "[마스토돈] 계정: @#{me}"
rescue => e
  puts "[마스토돈] 계정 확인 실패: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

# -------------------------
# Parser / Engine
# -------------------------
battle_engine = BattleEngine.new(mastodon, sheet_manager)
parser = CommandParser.new(mastodon, battle_engine)
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

        s = normalize_status(status)
        next unless s

        mention_id = hget(s, :id)
        next unless mention_id
        next if processed.include?(mention_id)

        created_at = hget(s, :created_at)
        created = Time.parse(created_at.to_s) rescue nil
        next unless created
        next if created < BOT_START_TIME

        processed.add(mention_id)

        acct_hash = hget(s, :account)
        sender = hget(acct_hash, :acct) || "unknown"
        puts "[스트리밍] #{mention_id} - @#{sender}"

        # ✅ 파서에는 “정상 status Hash”만 전달
        parser.parse(s)

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

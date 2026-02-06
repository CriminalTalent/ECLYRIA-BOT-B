# battle_bot.rb
require 'bundler/setup'
require 'dotenv/load'
require 'mastodon'
require 'set'

require_relative 'sheet_manager'
require_relative 'mastodon_client'
require_relative 'command_parser'

class BattleBot
  # ---- 단일 실행 락 (중복 실행 방지) ----
  LOCK_PATH = "/tmp/battle-bot.lock"
  # -------------------------------------

  def initialize
    # ---- 단일 실행 락 획득 ----
    @lock_file = File.open(LOCK_PATH, "w")
    unless @lock_file.flock(File::LOCK_EX | File::LOCK_NB)
      puts "[봇][pid=#{Process.pid}] 이미 실행 중입니다(락 존재). 종료합니다."
      exit 0
    end
    @lock_file.sync = true
    @lock_file.write("#{Process.pid}\n")
    # --------------------------

    # 중복 알림 처리 방지용 캐시
    @seen_notification_ids = Set.new

    # 환경 변수 로드
    @base_url = ENV['MASTODON_BASE_URL']
    @access_token = ENV['ACCESS_TOKEN']

    unless @base_url && @access_token
      puts "[봇][pid=#{Process.pid}] 오류: 환경 변수가 설정되지 않았습니다!"
      puts "MASTODON_BASE_URL: #{@base_url.nil? ? '없음' : '있음'}"
      puts "ACCESS_TOKEN: #{@access_token.nil? ? '없음' : '있음'}"
      exit 1
    end

    # SheetManager 초기화
    @sheet_manager = SheetManager.new

    # MastodonClient 초기화
    @mastodon_client = MastodonClient.new(@base_url, @access_token)

    # CommandParser 초기화
    @command_parser = CommandParser.new(@mastodon_client, @sheet_manager)

    puts "[봇][pid=#{Process.pid}] 초기화 완료"
  end

  def start
    puts "[봇][pid=#{Process.pid}] 시작..."

    begin
      @mastodon_client.stream do |notification|
        next unless notification.kind_of?(Mastodon::Notification)
        next unless notification.type == 'mention'

        # ---- 중복 알림(mention) 처리 방지 ----
        nid = notification.id.to_s
        if @seen_notification_ids.include?(nid)
          puts "[봇][pid=#{Process.pid}] 중복 알림 스킵: notification_id=#{nid}"
          next
        end
        @seen_notification_ids.add(nid)

        # 캐시가 무한히 커지지 않도록 상한 유지(최근 500개 정도)
        if @seen_notification_ids.size > 600
          @seen_notification_ids = Set.new(@seen_notification_ids.to_a.last(500))
        end
        # -------------------------------------

        status = notification.status
        next unless status && status.account

        begin
          content = status.content.to_s
          account = status.account

          # acct는 local이면 "user", remote면 "user@domain" 형태일 수 있음.
          # sender_id는 기존 로직대로 도메인을 제거해 유지.
          sender_id = account.acct.to_s.split('@').first

          # HTML 태그 제거
          clean_content = content.gsub(/<[^>]*>/, '').strip

          # ---- 멘션 태그 깨짐 복원: "@ Battle" -> "@Battle" ----
          clean_content = clean_content.gsub(/@\s+/, '@')
          # ----------------------------------------------------

          puts "[봇][pid=#{Process.pid}] 멘션 수신: #{sender_id} - #{clean_content[0..80]}"

          # 명령어 파싱 및 처리 (기존 기능 유지)
          @command_parser.parse_and_execute(clean_content, status, sender_id)

        rescue => e
          puts "[봇][pid=#{Process.pid}] 멘션 처리 오류: #{e.message}"
          puts e.backtrace[0..5]
        end
      end

    rescue => e
      puts "[봇][pid=#{Process.pid}] 스트리밍 오류: #{e.message}"
      puts e.backtrace[0..5]
      sleep 5
      retry
    end
  end
end

# 봇 실행 (기존 유지)
if __FILE__ == $0
  bot = BattleBot.new
  bot.start
end

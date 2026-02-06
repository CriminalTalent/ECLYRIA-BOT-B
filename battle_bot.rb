# battle_bot.rb
require 'bundler/setup'
require 'dotenv/load'
require 'mastodon'

require_relative 'sheet_manager'
require_relative 'mastodon_client'
require_relative 'command_parser'

class BattleBot
  def initialize
    # 환경 변수 로드
    @base_url = ENV['MASTODON_BASE_URL']
    @access_token = ENV['ACCESS_TOKEN']

    unless @base_url && @access_token
      puts "[봇] 오류: 환경 변수가 설정되지 않았습니다!"
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

    puts "[봇] 초기화 완료"
  end

  def start
    puts "[봇] 시작..."

    begin
      @mastodon_client.stream do |notification|
        next unless notification.kind_of?(Mastodon::Notification)
        next unless notification.type == 'mention'

        status = notification.status
        next unless status && status.account

        begin
          content = status.content.to_s
          account = status.account
          sender_id = account.acct.to_s.split('@').first  # 도메인 제거

          # HTML 태그 제거
          clean_content = content.gsub(/<[^>]*>/, '').strip

          puts "[봇] 멘션 수신: #{sender_id} - #{clean_content[0..50]}"

          # 명령어 파싱 및 처리
          @command_parser.parse_and_execute(clean_content, status, sender_id)
        rescue => e
          puts "[봇] 멘션 처리 오류: #{e.message}"
          puts e.backtrace[0..5]
        end
      end
    rescue => e
      puts "[봇] 스트리밍 오류: #{e.message}"
      puts e.backtrace[0..5]
      sleep 5
      retry
    end
  end
end

# 봇 실행
if __FILE__ == $0
  bot = BattleBot.new
  bot.start
end

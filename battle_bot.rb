# battle_bot.rb
# Mastodon 전투 봇 메인 파일 (자정 데미지 포함)

require 'mastodon'
require_relative 'core/sheet_manager'
require_relative 'core/midnight_damage'
require_relative 'command_parser'

class BattleBot
  def initialize
    # Mastodon 클라이언트 초기화
    @client = Mastodon::REST::Client.new(
      base_url: ENV['MASTODON_BASE_URL'],
      bearer_token: ENV['MASTODON_ACCESS_TOKEN']
    )
    
    # SheetManager 초기화
    @sheet_manager = SheetManager.new
    
    # CommandParser 초기화
    @parser = CommandParser.new(@client, @sheet_manager)
    
    # 자정 데미지 시스템 초기화 및 시작
    @midnight_damage = MidnightDamage.new(@client, @sheet_manager)
    @midnight_damage.start
    
    puts "[봇] 초기화 완료"
    puts "[봇] 자정 데미지 스케줄러 활성화됨"
  end

  # 봇 시작
  def start
    puts "[봇] 시작..."
    
    # 스트리밍 시작 (홈 타임라인)
    @client.stream('user') do |status|
      next unless status.is_a?(Mastodon::Status)
      
      # 멘션 필터링
      next unless status.mentions.any? { |m| m.acct == @client.verify_credentials.acct }
      
      # 명령어 처리
      @parser.handle(status)
    end
  rescue => e
    puts "[봇] 오류: #{e.message}"
    puts e.backtrace
    retry
  end

  # 봇 중지
  def stop
    @midnight_damage.stop
    puts "[봇] 중지됨"
  end

  # 수동으로 자정 데미지 실행 (테스트용)
  def test_midnight_damage
    puts "[테스트] 자정 데미지 수동 실행..."
    @midnight_damage.apply_now
  end
end

# 봇 실행
if __FILE__ == $0
  bot = BattleBot.new
  
  # Ctrl+C 처리
  trap('INT') do
    puts "\n[봇] 종료 중..."
    bot.stop
    exit
  end
  
  bot.start
end

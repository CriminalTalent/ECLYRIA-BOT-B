# commands/investigate_command.rb
require 'date'

class InvestigateCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '').strip
    sender_full = status.account.acct
    sender = sender_full.split('@').first
    in_reply_to_id = status.id

    kind = detect_kind(content)
    target = detect_target(content)
    
    unless kind && target
      puts "[조사] 명령어 파싱 실패: kind=#{kind}, target=#{target}"
      return
    end

    today = Date.today.to_s
    last_date = @sheet_manager.get_stat(sender, "마지막조사일")

    if last_date == today
      @mastodon_client.reply(sender, "오늘은 이미 조사를 진행하셨습니다.", in_reply_to_id: in_reply_to_id)
      return
    end

    row = @sheet_manager.find_investigation_data(target, kind)
    unless row
      @mastodon_client.reply(sender, "해당 대상에 대한 #{kind} 정보가 없습니다.", in_reply_to_id: in_reply_to_id)
      return
    end

    difficulty = row["난이도"].to_i
    luck_stat = @sheet_manager.get_stat(sender, "행운")
    stat = luck_stat ? luck_stat.to_i : 0
    dice = rand(1..20)
    result_value = dice + stat

    if result_value >= difficulty
      result_text = row["성공결과"]
    else
      result_text = row["실패결과"]
    end

    @sheet_manager.set_stat(sender, "마지막조사일", today)
    
    message = "#{sender}의 #{kind} 결과: #{result_text} (주사위: #{dice}, 보정: #{stat}, 총합: #{result_value}/#{difficulty})"
    @mastodon_client.say(message)
  end

  private

  def detect_kind(text)
    case text
    when /정밀조사/ then "정밀조사"
    when /감지/ then "감지"
    when /훔쳐보기/ then "훔쳐보기"
    when /조사/ then "조사"
    else nil
    end
  end

  def detect_target(text)
    match = text.match(/\[(.+?)\]/)
    match && match[1]
  end
end

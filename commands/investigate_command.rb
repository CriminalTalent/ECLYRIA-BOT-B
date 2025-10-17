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
    
    # DM이 아닌 경우 조사 불가
    if status.visibility != 'direct'
      @mastodon_client.reply(sender, "조사는 DM에서만 가능합니다. 저에게 DM으로 명령어를 보내주세요.", in_reply_to_id: in_reply_to_id)
      return
    end

    case content
    when /\[(조사|정밀조사|감지|훔쳐보기)\]\s+(.+)/
      kind = $1
      target = $2.strip
      investigate(sender, kind, target, in_reply_to_id)
    else
      return
    end
  end

  private

  def investigate(user_id, kind, target, reply_id)
    today = Date.today.to_s
    last_date_stat = @sheet_manager.get_stat(user_id, "마지막조사일")
    
    if last_date_stat == today
      @mastodon_client.dm(user_id, "오늘의 조사 기회를 모두 사용했습니다. 내일 다시 시도하세요.")
      return
    end

    rows = @sheet_manager.read_values("조사!A:E")
    return unless rows

    rows.each_with_index do |row, index|
      next if index == 0
      
      target_name = row[0]
      inv_kind = row[1]
      difficulty = row[2].to_i rescue 30
      success_result = row[3]
      fail_result = row[4]

      next unless target_name == target

      if inv_kind == kind || (kind == "조사" && inv_kind == "DM조사")
        luck_stat = @sheet_manager.get_stat(user_id, "행운")
        luck = luck_stat ? luck_stat.to_i : 10
        
        roll = rand(1..20)
        total = luck + roll
        
        success = total >= difficulty
        result = success ? success_result : fail_result
        
        @sheet_manager.set_stat(user_id, "마지막조사일", today)
        
        message = "조사 결과 (#{kind} - #{target})\n"
        message += "판정: #{total} (행운 #{luck} + 주사위 #{roll}) vs 난이도 #{difficulty}\n"
        message += "결과: #{result}"
        
        @mastodon_client.dm(user_id, message)
        return
      end
    end
    
    @mastodon_client.dm(user_id, "#{target}에 대한 #{kind} 항목을 찾을 수 없습니다.")
  end
end

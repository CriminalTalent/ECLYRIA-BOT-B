class InvestigateCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def investigate(text, user_id, reply_id)
    match = text.match(/\[(조사|정밀조사|감지|훔쳐보기)\]\s*(.+)/i)
    kind = match[1]
    target = match[2].strip
    
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_id, "등록되지 않은 사용자입니다.", visibility: 'direct')
      return
    end
    
    row = @sheet_manager.find_investigation_data(target, kind)
    unless row
      @mastodon_client.reply(reply_id, "#{target}에 대한 #{kind} 정보가 없습니다.", visibility: 'direct')
      return
    end
    
    difficulty = row["난이도"].to_i
    luck = (user["행운"] || 0).to_i
    dice = rand(1..20)
    total = luck + dice
    
    success = total >= difficulty
    result = success ? row["성공결과"] : row["실패결과"]
    
    message = "#{kind} 판정: #{dice} + #{luck} = #{total} (난이도: #{difficulty})\n"
    message += success ? "성공\n" : "실패\n"
    message += result
    
    @mastodon_client.dm(user_id, message)
    
    today = Time.now.strftime('%Y-%m-%d')
    @sheet_manager.update_stat(user_id, "마지막조사일", today)
  end
end

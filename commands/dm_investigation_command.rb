class DMInvestigationCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def send_result(text, dm_id, reply_id)
    match = text.match(/DM조사결과\s+@(\S+)\s+(.+)/i)
    target_username = match[1]
    result_text = match[2]
    
    accounts = @mastodon_client.account_search(target_username)
    if accounts.empty?
      @mastodon_client.reply(reply_id, "#{target_username} 사용자를 찾을 수 없습니다.", visibility: 'direct')
      return
    end
    
    account = accounts.first
    base_domain = ENV['MASTODON_BASE_URL'].split('//').last
    target_id = "@#{account['username']}@#{base_domain}"
    
    user = @sheet_manager.find_user(target_id)
    unless user
      @mastodon_client.reply(reply_id, "#{target_id}는 등록되지 않은 사용자입니다.", visibility: 'direct')
      return
    end
    
    @mastodon_client.dm(target_id, result_text)
    
    today = Time.now.strftime('%Y-%m-%d')
    @sheet_manager.update_stat(target_id, "마지막조사일", today)
    
    @mastodon_client.reply(reply_id, "#{target_id}에게 조사 결과를 전송했습니다.", visibility: 'direct')
  end
end

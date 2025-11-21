class DMInvestigationCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def send_result(text, user_id, reply_status)
    match = text.match(/DM조사결과\s+@(\S+)\s+(.+)/i)
    unless match
      @mastodon_client.reply(reply_status, "형식이 올바르지 않습니다. 사용법: DM조사결과 @사용자 결과내용")
      return
    end

    target_username = match[1]
    result_text = match[2]
    
    # 간단하게 @아이디 형식으로 처리
    base_domain = ENV['MASTODON_BASE_URL'].split('//').last
    target_id = target_username.start_with?('@') ? target_username : "@#{target_username}"
    
    # 도메인이 없으면 추가
    unless target_id.include?('@', 1)  # 첫 @를 제외하고 @가 있는지
      target_id = "#{target_id}@#{base_domain}"
    end
    
    user = @sheet_manager.find_user(target_id)
    unless user
      @mastodon_client.reply(reply_status, "#{target_id}는 등록되지 않은 사용자입니다.")
      return
    end
    
    # 대상에게 DM 전송
    @mastodon_client.dm(target_id, result_text)
    
    # 조사일 업데이트
    today = Time.now.strftime('%Y-%m-%d')
    @sheet_manager.update_stat(target_id, "마지막조사일", today, :set)
    
    # 발신자에게 확인 메시지
    @mastodon_client.reply(reply_status, "#{target_id}에게 조사 결과를 전송했습니다.")
  end
end

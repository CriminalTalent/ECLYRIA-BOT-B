require_relative '../core/battle_state'

class PotionCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def use_potion(user_id, reply_id)
    unless BattleState.active?
      @mastodon_client.reply(reply_id, "전투 중에만 물약을 사용할 수 있습니다.", visibility: 'direct')
      return
    end

    state = BattleState.get
    unless state[:current_turn] == user_id
      @mastodon_client.reply(reply_id, "당신의 턴이 아닙니다.", visibility: 'direct')
      return
    end

    user = @sheet_manager.find_user(user_id)
    items = user["아이템"] || ""
    
    unless items.include?("포션")
      message = "포션이 없습니다."
      @mastodon_client.post(message, visibility: 'public')
      BattleState.get[:participants].each do |p_id|
        next if p_id.include?("허수아비")
        @mastodon_client.dm(p_id, message)
      end
      return
    end

    heal_amount = [5, 10, 15, 20].sample
    current_hp = user["체력"].to_i
    new_hp = [current_hp + heal_amount, 100].min
    
    @sheet_manager.update_stat(user_id, "체력", new_hp)
    
    new_items = items.sub("포션", "").strip
    @sheet_manager.update_stat(user_id, "아이템", new_items)
    
    user_name = user["이름"] || user_id
    message = "#{user_name}이(가) 물약을 사용했습니다. (회복량: #{heal_amount}, 현재 체력: #{new_hp})"
    
    @mastodon_client.post(message, visibility: 'public')
    
    BattleState.get[:participants].each do |p_id|
      next if p_id.include?("허수아비")
      @mastodon_client.dm(p_id, message)
    end
    
    BattleState.next_turn
  end
end

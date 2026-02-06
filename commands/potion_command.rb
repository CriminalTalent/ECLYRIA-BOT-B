# commands/potion_command.rb

require_relative '../state/battle_state'

class PotionCommand
  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager
  end

  # 전투 중 물약 사용
  def use_potion_in_battle(user_id, potion_size, target_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 턴 확인
    unless state[:current_turn] == user_id
      @client.reply(reply_status, "@#{user_id} 당신의 차례가 아닙니다.")
      return
    end
    
    user = @sheet_manager.find_user(user_id)
    items_str = user["아이템"] || ""
    items = parse_items(items_str)
    
    # 물약 종류 확인
    potion_key = case potion_size
    when "소형", "소형물약"
      "소형물약"
    when "중형", "중형물약"
      "중형물약"
    when "대형", "대형물약"
      "대형물약"
    else
      @client.reply(reply_status, "@#{user_id} 알 수 없는 물약입니다. (소형/중형/대형)")
      return
    end
    
    # 물약 보유 확인
    unless items[potion_key] && items[potion_key] > 0
      @client.reply(reply_status, "@#{user_id} #{potion_key}이(가) 없습니다.")
      return
    end
    
    # 회복량 설정
    heal_amount = case potion_key
    when "소형물약" then 10
    when "중형물약" then 30
    when "대형물약" then 50
    end
    
    # 대상 결정
    heal_target_id = target_id || user_id
    heal_target = @sheet_manager.find_user(heal_target_id)
    
    unless heal_target
      @client.reply(reply_status, "@#{heal_target_id} 사용자를 찾을 수 없습니다.")
      return
    end
    
    # 팀전에서 아군인지 확인
    if state[:type] == "2v2" || state[:type] == "4v4"
      user_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      target_team = state[:teams][:team1].include?(heal_target_id) ? :team1 : :team2
      
      if user_team != target_team
        @client.reply(reply_status, "@#{user_id} 아군에게만 물약을 사용할 수 있습니다.")
        return
      end
    end
    
    # 물약 사용
    current_hp = (heal_target["HP"] || 0).to_i
    max_hp = 100 + ((heal_target["체력"] || 10).to_i * 10)
    new_hp = [current_hp + heal_amount, max_hp].min
    
    @sheet_manager.update_user(heal_target_id, { "HP" => new_hp })
    
    # 물약 감소
    items[potion_key] -= 1
    items.delete(potion_key) if items[potion_key] <= 0
    new_items_str = items.map { |k, v| "#{k}:#{v}" }.join(", ")
    @sheet_manager.update_user(user_id, { "아이템" => new_items_str })
    
    # 메시지 전송
    user_name = user["이름"] || user_id
    target_name = heal_target["이름"] || heal_target_id
    
    message = "#{user_name}이(가) #{potion_key} 사용!\n"
    if user_id == heal_target_id
      message += "HP +#{heal_amount} (#{current_hp} → #{new_hp})\n"
    else
      message += "#{target_name}의 HP +#{heal_amount} (#{current_hp} → #{new_hp})\n"
    end
    
    # 다음 턴으로
    if state[:type] == "pvp"
      opponent_id = state[:participants].find { |p| p != user_id }
      state[:current_turn] = opponent_id
      state[:round] += 1
      BattleState.update(battle_id, state)
      
      opponent = @sheet_manager.find_user(opponent_id)
      opponent_name = opponent["이름"] || opponent_id
      
      message += "\n#{opponent_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용/크기]"
    else
      # 팀전 다음 턴
      next_turn_multi(state, battle_id)
      next_user = @sheet_manager.find_user(state[:current_turn])
      next_name = next_user["이름"] || state[:current_turn]
      
      message += "\n#{next_name}의 차례\n"
      message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
    end
    
    @client.reply({ "uri" => state[:thread_ts] }, message)
  end

  # 일상에서 물약 사용 (전투 밖)
  def use_potion_casual(user_id, potion_size, reply_status)
    user = @sheet_manager.find_user(user_id)
    
    unless user
      @client.reply(reply_status, "@#{user_id} 사용자를 찾을 수 없습니다.")
      return
    end
    
    items_str = user["아이템"] || ""
    items = parse_items(items_str)
    
    # 물약 종류 확인
    potion_key = case potion_size
    when "소형", "소형물약"
      "소형물약"
    when "중형", "중형물약"
      "중형물약"
    when "대형", "대형물약"
      "대형물약"
    else
      @client.reply(reply_status, "@#{user_id} 알 수 없는 물약입니다. (소형/중형/대형)")
      return
    end
    
    # 물약 보유 확인
    unless items[potion_key] && items[potion_key] > 0
      @client.reply(reply_status, "@#{user_id} #{potion_key}이(가) 없습니다.")
      return
    end
    
    # 회복량 설정
    heal_amount = case potion_key
    when "소형물약" then 10
    when "중형물약" then 30
    when "대형물약" then 50
    end
    
    # 현재 체력
    current_hp = (user["HP"] || 0).to_i
    max_hp = 100 + ((user["체력"] || 10).to_i * 10)
    
    # 이미 최대 체력이면
    if current_hp >= max_hp
      @client.reply(reply_status, "@#{user_id} 이미 체력이 최대입니다! (#{current_hp}/#{max_hp})")
      return
    end
    
    # 물약 사용
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp
    @sheet_manager.update_user(user_id, { "HP" => new_hp })
    
    # 물약 감소
    items[potion_key] -= 1
    items.delete(potion_key) if items[potion_key] <= 0
    new_items_str = items.map { |k, v| "#{k}:#{v}" }.join(", ")
    @sheet_manager.update_user(user_id, { "아이템" => new_items_str })
    
    user_name = user["이름"] || user_id
    hp_bar = generate_hp_bar(new_hp, max_hp)
    
    message = "💊 #{user_name}이(가) #{potion_key} 사용!\n"
    message += "HP +#{actual_heal} (#{current_hp} → #{new_hp})\n"
    message += "#{hp_bar} #{new_hp}/#{max_hp}"
    
    @client.reply(reply_status, message)
  end

  private

  # 아이템 파싱
  def parse_items(items_str)
    items = {}
    return items if items_str.nil? || items_str.strip.empty?
    
    items_str.split(',').each do |item|
      parts = item.strip.split(':')
      next if parts.length != 2
      
      name = parts[0].strip
      count = parts[1].strip.to_i
      items[name] = count if count > 0
    end
    
    items
  end

  # 팀전 다음 턴
  def next_turn_multi(state, battle_id)
    turn_order = state[:turn_order]
    current_index = turn_order.index(state[:current_turn])
    
    # 다음 살아있는 참가자 찾기
    next_index = (current_index + 1) % turn_order.length
    tried = 0
    
    while tried < turn_order.length
      next_user_id = turn_order[next_index]
      next_user = @sheet_manager.find_user(next_user_id)
      
      if (next_user["HP"] || 0).to_i > 0
        state[:current_turn] = next_user_id
        state[:round] += 1 if next_index == 0
        BattleState.update(battle_id, state)
        return
      end
      
      next_index = (next_index + 1) % turn_order.length
      tried += 1
    end
  end

  # HP바 생성
  def generate_hp_bar(current_hp, max_hp)
    return "██████████" if current_hp >= max_hp
    return "░░░░░░░░░░" if current_hp <= 0 || max_hp <= 0
    
    hp_percent = (current_hp.to_f / max_hp.to_f * 100).round
    filled = (hp_percent / 10.0).floor
    empty = 10 - filled
    
    "█" * filled + "░" * empty
  end
end

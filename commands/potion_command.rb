require_relative '../core/battle_state'
require_relative '../core/battle_engine'

class PotionCommand
  POTION_EFFECTS = {
    "소형" => 10,
    "중형" => 30,
    "대형" => 50
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  # 평상시 물약 사용 (전투 외)
  def use_potion(user_id, reply_status, potion_type)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_status, "등록되지 않은 사용자입니다.")
      return
    end

    # 전투 중인지 확인
    battle_id = BattleState.find_battle_id_by_user(user_id)
    if battle_id
      # 전투 중이면 BattleEngine을 통해 처리
      state = BattleState.get(battle_id)
      if state
        engine = BattleEngine.new(@mastodon_client, @sheet_manager)
        engine.use_potion(user_id, potion_type, nil)
        return
      end
    end

    # 평상시 물약 사용
    use_potion_outside_battle(user_id, reply_status, potion_type, user)
  end

  # 팀전투에서 아군에게 물약 사용
  def use_potion_for_target(user_id, reply_status, potion_type, target_id)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)

    unless state
      @mastodon_client.reply(reply_status, "현재 전투 중이 아닙니다.")
      return
    end

    unless state[:participants].include?(target_id)
      @mastodon_client.reply(reply_status, "전투 참가자가 아닙니다.")
      return
    end

    # BattleEngine을 통해 처리
    engine = BattleEngine.new(@mastodon_client, @sheet_manager)
    engine.use_potion(user_id, potion_type, target_id)
  end

  private

  # 전투 외 물약 사용
  def use_potion_outside_battle(user_id, reply_status, potion_type, user)
    potion_name = "#{potion_type}물약"
    heal_amount = POTION_EFFECTS[potion_type]

    unless heal_amount
      @mastodon_client.reply(reply_status, "알 수 없는 물약 종류입니다.")
      return
    end

    # 아이템 배열 처리 (Array 또는 String)
    items = user["아이템"]
    items = items.is_a?(Array) ? items : items.to_s.split(',').map(&:strip)

    unless items.include?(potion_name)
      @mastodon_client.reply(reply_status, "#{potion_name}을(를) 보유하고 있지 않습니다.")
      return
    end

    # 물약 제거
    items.delete_at(items.index(potion_name))

    # 체력 회복
    current_hp = (user["HP"] || 100).to_i
    vitality_stat = (user["체력"] || 0).to_i
    max_hp = 100 + (vitality_stat * 10)
    new_hp = [current_hp + heal_amount, max_hp].min

    @sheet_manager.update_user(user_id, {
      "HP" => new_hp,
      "아이템" => items.is_a?(Array) ? items.join(',') : items
    })

    user_name = user["이름"] || user_id
    hp_bar = create_hp_bar(new_hp, max_hp)

    message = "#{user_name}이(가) #{potion_name} 사용!\n"
    message += "HP +#{heal_amount} (#{current_hp} → #{new_hp})\n"
    message += "#{hp_bar} #{new_hp}/#{max_hp}"

    @mastodon_client.reply(reply_status, message)
  end

  def create_hp_bar(current_hp, max_hp)
    percentage = [current_hp.to_f / max_hp, 1.0].min
    filled_length = (percentage * 10).round

    filled = "█" * filled_length
    empty = "░" * (10 - filled_length)

    filled + empty
  end
end

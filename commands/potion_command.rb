# commands/potion_command.rb

class PotionCommand
  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager
  end

  # 일상에서 물약 사용 (전투 밖)
  def use_potion_casual(user_id, potion_size, reply_status)
    user = @sheet_manager.find_user(user_id)

    unless user
      @client.reply(reply_status, "@#{user_id} 사용자를 찾을 수 없습니다.")
      return
    end

    items = user["아이템"] || []

    # 물약 키 변환
    potion_key = case potion_size
                 when "소형", "소형물약" then "소형물약"
                 when "중형", "중형물약" then "중형물약"
                 when "대형", "대형물약" then "대형물약"
                 else
                   @client.reply(reply_status, "@#{user_id} 알 수 없는 물약입니다. (소형/중형/대형)")
                   return
                 end

    # 물약 보유 확인
    unless items.include?(potion_key)
      @client.reply(reply_status, "@#{user_id} #{potion_key}이(가) 없습니다.")
      return
    end

    # 회복량 결정
    heal_amount = case potion_key
                  when "소형물약" then 10
                  when "중형물약" then 30
                  when "대형물약" then 50
                  end

    current_hp = (user["HP"] || 0).to_i
    max_hp = 100 + ((user["체력"] || 10).to_i * 10)

    if current_hp >= max_hp
      @client.reply(reply_status, "@#{user_id} 이미 체력이 최대입니다! (#{current_hp}/#{max_hp})")
      return
    end

    # 물약 사용
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp
    @sheet_manager.update_user(user_id, { "HP" => new_hp })

    # 물약 제거
    items.delete_at(items.index(potion_key))  # 하나만 제거
    new_items_str = items.join(", ")
    @sheet_manager.update_user(user_id, { "아이템" => new_items_str })

    user_name = user["이름"] || user_id
    hp_bar = generate_hp_bar(new_hp, max_hp)

    message = <<~MSG
      @#{user_id}

      #{user_name}이(가) #{potion_key} 사용!
      HP +#{actual_heal} (#{current_hp} → #{new_hp})
      #{hp_bar} #{new_hp}/#{max_hp}
    MSG

    @client.reply(reply_status, message.strip)
  end

  private

  def generate_hp_bar(current_hp, max_hp)
    return "██████████" if current_hp >= max_hp
    return "░░░░░░░░░░" if current_hp <= 0 || max_hp <= 0

    percent = (current_hp.to_f / max_hp.to_f * 100).round
    filled = (percent / 10.0).floor
    empty = 10 - filled
    "█" * filled + "░" * empty
  end
end

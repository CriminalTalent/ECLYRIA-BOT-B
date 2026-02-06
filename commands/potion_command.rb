# commands/potion_command.rb
# 체력바 적용 및 이모지 제거 버전

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

    items = user["아이템"] || ""
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
    max_hp = calculate_max_hp(user)
    
    if current_hp >= max_hp
      hp_bar = generate_hp_bar(current_hp, max_hp)
      @client.reply(reply_status, "@#{user_id} 이미 체력이 최대입니다! #{hp_bar}")
      return
    end

    # 물약 사용
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp
    @sheet_manager.update_user(user_id, { "HP" => new_hp })

    # 물약 제거 (문자열에서 첫 번째 발견된 물약 제거)
    new_items = remove_item_from_string(items, potion_key)
    @sheet_manager.update_user(user_id, { "아이템" => new_items })

    user_name = user["이름"] || user_id
    hp_bar = generate_hp_bar(new_hp, max_hp)
    
    message = <<~MSG
      @#{user_id}
      #{user_name}이(가) #{potion_key} 사용!
      HP +#{actual_heal} (#{current_hp} -> #{new_hp})
      #{hp_bar}
    MSG

    @client.reply(reply_status, message.strip)
  end

  private

  def calculate_max_hp(user)
    base_hp = 100
    vitality_bonus = ((user["체력"] || 10).to_i * 10)
    base_hp + vitality_bonus
  end

  def generate_hp_bar(current_hp, max_hp, bar_length = 10)
    return "█" * bar_length + " #{current_hp}/#{max_hp}" if current_hp >= max_hp
    return "░" * bar_length + " #{current_hp}/#{max_hp}" if current_hp <= 0 || max_hp <= 0
    
    filled_length = ((current_hp.to_f / max_hp.to_f) * bar_length).round
    empty_length = bar_length - filled_length
    
    "█" * filled_length + "░" * empty_length + " #{current_hp}/#{max_hp}"
  end

  def remove_item_from_string(items_string, item_to_remove)
    # 아이템을 쉼표로 분리
    items_array = items_string.split(',').map(&:strip)
    
    # 첫 번째 발견된 아이템 제거
    remove_index = items_array.index(item_to_remove)
    if remove_index
      items_array.delete_at(remove_index)
    end
    
    # 다시 문자열로 합치기
    items_array.join(', ')
  end
end

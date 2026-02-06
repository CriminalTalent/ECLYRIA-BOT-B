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
    
    message = "@#{user_id}\n\n"
    message += "#{user_name}이(가) #{potion_key} 사용!\n"
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

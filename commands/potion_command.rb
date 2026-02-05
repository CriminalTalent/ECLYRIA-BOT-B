# commands/potion_command.rb
# 물약 사용 명령어 (D열 아이템란 연동)

class PotionCommand
  # 물약 크기별 회복량
  POTION_HEAL = {
    "소형" => 10,
    "중형" => 30,
    "대형" => 50
  }.freeze

  def initialize(mastodon_client, sheet_manager)
    @client = mastodon_client
    @sheet_manager = sheet_manager
  end

  # 본인에게 물약 사용
  def use_potion(user_id, reply_status, potion_type = "소형")
    user = @sheet_manager.find_user(user_id)
    
    unless user
      @client.reply(reply_status, "@#{user_id} 사용자를 찾을 수 없습니다.")
      return
    end

    # 물약 회복량
    heal_amount = POTION_HEAL[potion_type] || POTION_HEAL["소형"]
    
    # D열 아이템란에서 물약 확인
    potion_key = "#{potion_type}물약"
    current_potions = parse_items(user["아이템"] || "")
    
    unless current_potions[potion_key] && current_potions[potion_key] > 0
      @client.reply(reply_status, "@#{user_id} #{potion_type} 물약이 없습니다.")
      return
    end

    # 현재 HP
    current_hp = (user["HP"] || 0).to_i
    max_hp = calculate_max_hp(user)
    
    if current_hp >= max_hp
      @client.reply(reply_status, "@#{user_id} 이미 체력이 가득 찼습니다. (#{current_hp}/#{max_hp})")
      return
    end

    # HP 회복
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp
    
    # 물약 차감
    current_potions[potion_key] -= 1
    new_items = build_items_string(current_potions)
    
    # 업데이트
    @sheet_manager.update_user(user_id, { 
      hp: new_hp,
      items: new_items
    })

    user_name = user["이름"] || user_id
    message = "@#{user_id} #{user_name}이(가) #{potion_type} 물약을 사용했습니다.\n"
    message += "회복: +#{actual_heal} HP\n"
    message += "현재 HP: #{new_hp}/#{max_hp}"
    
    @client.reply(reply_status, message)
  end

  # 아군에게 물약 사용
  def use_potion_for_target(user_id, reply_status, potion_type = "소형", target_id)
    user = @sheet_manager.find_user(user_id)
    target = @sheet_manager.find_user(target_id)
    
    unless user
      @client.reply(reply_status, "@#{user_id} 사용자를 찾을 수 없습니다.")
      return
    end
    
    unless target
      @client.reply(reply_status, "@#{target_id} 대상을 찾을 수 없습니다.")
      return
    end

    # 물약 회복량
    heal_amount = POTION_HEAL[potion_type] || POTION_HEAL["소형"]
    
    # 사용자의 D열 아이템란에서 물약 확인
    potion_key = "#{potion_type}물약"
    current_potions = parse_items(user["아이템"] || "")
    
    unless current_potions[potion_key] && current_potions[potion_key] > 0
      @client.reply(reply_status, "@#{user_id} #{potion_type} 물약이 없습니다.")
      return
    end

    # 대상 현재 HP
    current_hp = (target["HP"] || 0).to_i
    max_hp = calculate_max_hp(target)
    
    if current_hp >= max_hp
      target_name = target["이름"] || target_id
      @client.reply(reply_status, "@#{target_id} #{target_name}의 체력이 이미 가득 찼습니다. (#{current_hp}/#{max_hp})")
      return
    end

    # HP 회복
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp
    
    # 물약 차감
    current_potions[potion_key] -= 1
    new_items = build_items_string(current_potions)
    
    # 업데이트
    @sheet_manager.update_user(user_id, { 
      items: new_items
    })
    
    @sheet_manager.update_user(target_id, { 
      hp: new_hp
    })

    user_name = user["이름"] || user_id
    target_name = target["이름"] || target_id
    
    message = "@#{user_id} #{user_name}이(가) @#{target_id} #{target_name}에게 #{potion_type} 물약을 사용했습니다.\n"
    message += "회복: +#{actual_heal} HP\n"
    message += "현재 HP: #{new_hp}/#{max_hp}"
    
    @client.reply(reply_status, message)
  end

  private

  # 최대 HP 계산
  def calculate_max_hp(user)
    vitality = (user["체력"] || user[:vitality] || 10).to_i
    base_hp = 100
    max_hp = base_hp + (vitality * 10)
    max_hp
  end

  # 아이템 문자열 파싱 (D열)
  # 예: "소형물약:3, 중형물약:1, 대형물약:0"
  def parse_items(items_string)
    items = {}
    
    return items if items_string.nil? || items_string.strip.empty?
    
    items_string.split(',').each do |item|
      item = item.strip
      if item =~ /^(.+?):(\d+)$/
        item_name = $1.strip
        count = $2.to_i
        items[item_name] = count
      end
    end
    
    items
  end

  # 아이템 딕셔너리를 문자열로 변환
  def build_items_string(items_hash)
    items_hash.map { |name, count| "#{name}:#{count}" }.join(", ")
  end
end

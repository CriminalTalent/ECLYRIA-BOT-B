# commands/heal_command.rb
# 전투 외 물약 사용 명령어

class HealCommand
  # 물약 종류별 회복량 (고정값)
  POTION_TYPES = {
    "소형 포션" => 20,
    "중형 포션" => 40,
    "대형 포션" => 60,
    "포션" => 20,      # 기본 포션
    "물약" => 20        # 기본 물약
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def use_potion(user_id, reply_status)
    user = @sheet_manager.find_user(user_id)
    
    unless user
      @mastodon_client.reply(reply_status, "@#{user_id} 등록되지 않은 사용자입니다.")
      return
    end

    # 아이템 확인
    items = user["아이템"] || user[:items] || ""
    potion_found = nil
    heal_amount = 0

    # 우선순위: 대형 → 중형 → 소형 → 기본
    POTION_TYPES.keys.reverse.each do |potion_type|
      if items.include?(potion_type)
        potion_found = potion_type
        heal_amount = POTION_TYPES[potion_type]
        break
      end
    end

    unless potion_found
      @mastodon_client.reply(reply_status, "@#{user_id} 포션이 없습니다.")
      return
    end

    # 현재 체력
    current_hp = (user["HP"] || user[:hp] || 100).to_i
    
    # 이미 최대 체력이면
    if current_hp >= 100
      @mastodon_client.reply(reply_status, "@#{user_id} 이미 최대 체력입니다. (100/100)")
      return
    end

    # 회복
    new_hp = [current_hp + heal_amount, 100].min
    actual_heal = new_hp - current_hp

    # HP 업데이트
    @sheet_manager.update_user(user_id, { hp: new_hp })

    # 포션 제거 (정확히 일치하는 것만 제거)
    new_items = items.sub(potion_found, "").gsub(/,+/, ",").gsub(/^,|,$/, "").strip
    @sheet_manager.update_user(user_id, { items: new_items })

    name = user["이름"] || user[:name] || user_id
    
    msg = "@#{user_id}\n"
    msg += "━━━━━━━━━━━━━━━━━━\n"
    msg += "#{name}이(가) #{potion_found}을 사용했습니다.\n"
    msg += "━━━━━━━━━━━━━━━━━━\n"
    msg += "회복량: #{actual_heal}\n"
    msg += "체력: #{current_hp} → #{new_hp}\n"
    msg += "━━━━━━━━━━━━━━━━━━"

    @mastodon_client.reply(reply_status, msg)
  end
end

# commands/hp_command.rb
# 체력 확인 명령어

class HpCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def check_hp(user_id, reply_status)
    user = @sheet_manager.find_user(user_id)
    
    unless user
      @mastodon_client.reply(
        reply_status,
        "@#{user_id} 등록되지 않은 사용자입니다. 먼저 입학 절차를 진행해주세요."
      )
      return
    end

    # 이름과 HP 정보 추출
    name = user[:name] || user["이름"] || user_id
    hp = (user[:hp] || user["HP"] || 0).to_i
    
    # 최대 HP는 100으로 고정
    max_hp = 100

    # HP 퍼센트 계산
    hp_percent = max_hp > 0 ? (hp.to_f / max_hp.to_f * 100).round(1) : 0

    # HP 바 생성 (10칸)
    filled = (hp_percent / 10).floor
    empty = 10 - filled
    hp_bar = "█" * filled + "░" * empty

    # 상태 판단
    status = case hp_percent
             when 0 then "전투불가"
             when 1..20 then "위험"
             when 21..50 then "부상"
             when 51..80 then "양호"
             else "건강"
             end

    # 메시지 구성
    msg = "@#{user_id}\n"
    msg += "━━━━━━━━━━━━━━━━━━\n"
    msg += "【 #{name}의 상태 】\n"
    msg += "━━━━━━━━━━━━━━━━━━\n\n"
    msg += "HP: #{hp}/#{max_hp} (#{hp_percent}%)\n"
    msg += "#{hp_bar}\n"
    msg += "상태: #{status}\n"
    msg += "━━━━━━━━━━━━━━━━━━"

    @mastodon_client.reply(reply_status, msg)
  rescue => e
    puts "[HpCommand 오류] #{e.class}: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(
      reply_status,
      "@#{user_id} 체력 확인 중 오류가 발생했습니다."
    )
  end
end

# core/battle_engine.rb
# UTF-8

class BattleEngine
  INITIAL_HP = 100

  def initialize(sheet_manager)
    @sheet_manager = sheet_manager
    @states = @sheet_manager.get_battle_states || {}
    @cache_time = Time.now
  end

  # =======================
  #  유틸
  # =======================
  def log(msg)
    puts "[BattleEngine] #{msg}"
  end

  def save!
    @sheet_manager.save_battle_states(@states)
    log("상태 저장됨: #{@states.keys.size}개 전투")
  end

  def find_battle_by_user(user)
    @states.values.find { |s| s[:players].include?(user) }
  end

  # =======================
  #  전투 생성
  # =======================
  def start_1v1(p1, p2)
    # 이미 전투 중인 플레이어가 있으면 X
    if find_battle_by_user(p1) || find_battle_by_user(p2)
      return "⚠ 두 플레이어 중 누군가 이미 전투 중입니다."
    end

    id = "battle_#{Time.now.to_i}_#{rand(10000)}"
    turn_order = [p1, p2].shuffle

    @states[id] = {
      type: "1v1",
      players: [p1, p2],
      hp: {
        p1 => INITIAL_HP,
        p2 => INITIAL_HP
      },
      turn: turn_order.first
    }

    save!

    "#{p1} vs #{p2} 전투 시작! 첫 공격 턴: #{turn_order.first}"
  end

  # =======================
  #  행동 처리
  # =======================
  def attack(user)
    battle = find_battle_by_user(user)
    return "⚠ 전투 중이 아닙니다." unless battle

    return "⚠ 아직 #{battle[:turn]} 턴입니다." unless battle[:turn] == user

    enemy = (battle[:players] - [user]).first
    damage = rand(10..25)
    battle[:hp][enemy] -= damage

    log("#{user} → #{enemy}: #{damage} 피해! HP=#{battle[:hp][enemy]}")

    result = "#{user}의 공격! #{enemy}에게 #{damage}의 피해!"

    if battle[:hp][enemy] <= 0
      result += "\n🎉 #{user} 승리! 전투 종료!"
      @states.delete(battle.key(battle))
    else
      battle[:turn] = enemy
      result += "\n🔁 다음 턴: #{enemy}"
    end

    save!
    result
  end

  def defend(user)
    battle = find_battle_by_user(user)
    return "⚠ 전투 중이 아닙니다." unless battle

    return "⚠ 아직 #{battle[:turn]} 턴입니다." unless battle[:turn] == user

    heal = rand(5..15)
    battle[:hp][user] += heal

    battle[:turn] = (battle[:players] - [user]).first
    save!

    "#{user}는 방어 태세! HP +#{heal}\n🔁 다음 턴: #{battle[:turn]}"
  end

  def flee(user)
    battle = find_battle_by_user(user)
    return "⚠ 전투 중이 아닙니다." unless battle

    winner = (battle[:players] - [user]).first
    @states.delete(battle.key(battle))
    save!

    "🏳 #{user} 도망! #{winner} 승리!"
  end

  # =======================
  #  상태 조회
  # =======================
  def status(user = nil)
    if user
      battle = find_battle_by_user(user)
      return "⚠ 전투 중이 아닙니다." unless battle

      p1, p2 = battle[:players]
      return "📊 HP: #{p1}=#{battle[:hp][p1]}, #{p2}=#{battle[:hp][p2]}"
    end

    return "🚫 활성 전투 없음" if @states.empty?

    list = @states.values.map { |b| "#{b[:players].join(' vs ')} (턴: #{b[:turn]})" }
    "⚔ 활성 전투\n" + list.join("\n")
  end
end

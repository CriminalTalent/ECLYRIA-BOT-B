# commands/battle_command.rb

require_relative '../core/battle_engine'
require_relative '../core/battle_state'

class BattleCommand
  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager
    @engine = BattleEngine.new(@client, @sheet_manager)
  end

  # 1:1 전투 시작
  def start_1v1(user_id, opponent_id, reply_status)
    user = @sheet_manager.find_user(user_id)
    opponent = @sheet_manager.find_user(opponent_id)

    unless user
      @client.reply(reply_status, "@#{user_id} 사용자를 찾을 수 없습니다.")
      return
    end

    unless opponent
      @client.reply(reply_status, "@#{opponent_id} 사용자를 찾을 수 없습니다.")
      return
    end

    @engine.start_battle(user_id, opponent_id, reply_status)
  end

  # 2:2 전투 시작
  def start_2v2(p1, p2, p3, p4, reply_status)
    participants = [p1, p2, p3, p4]

    if participants.uniq.length != 4
      @client.reply(reply_status, "참가자가 중복되었습니다!")
      return
    end

    participants.each do |pid|
      unless @sheet_manager.find_user(pid)
        @client.reply(reply_status, "@#{pid} 사용자를 찾을 수 없습니다.")
        return
      end
    end

    @engine.start_2v2_battle([p1, p2], [p3, p4], reply_status)
  end

  # 4:4 전투 시작
  def start_4v4(p1, p2, p3, p4, p5, p6, p7, p8, reply_status)
    participants = [p1, p2, p3, p4, p5, p6, p7, p8]

    if participants.uniq.length != 8
      @client.reply(reply_status, "참가자가 중복되었습니다!")
      return
    end

    participants.each do |pid|
      unless @sheet_manager.find_user(pid)
        @client.reply(reply_status, "@#{pid} 사용자를 찾을 수 없습니다.")
        return
      end
    end

    @engine.start_4v4_battle([p1, p2, p3, p4], [p5, p6, p7, p8], reply_status)
  end

  # 공격
  def attack(user_id, target_id, reply_status)
    state, battle_id = get_battle_and_state(user_id, reply_status)
    return unless state

    if state[:actions]&.key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end

    case state[:type]
    when "pvp"
      opponent_id = state[:participants].find { |p| p != user_id }
      @engine.register_action(user_id, :attack, opponent_id, battle_id)
    when "2v2", "4v4"
      unless target_id
        @client.reply(reply_status, "@#{user_id} 팀 전투에서는 [공격/@대상]으로 지정해야 합니다.")
        return
      end
      @engine.register_action(user_id, :attack, target_id, battle_id)
    end
  end

  # 방어
  def defend(user_id, target_id, reply_status)
    state, battle_id = get_battle_and_state(user_id, reply_status)
    return unless state

    if state[:actions]&.key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end

    defend_target = target_id || user_id

    if %w[2v2 4v4].include?(state[:type]) && target_id
      unless same_team?(state, user_id, target_id)
        @client.reply(reply_status, "@#{user_id} 아군만 방어할 수 있습니다.")
        return
      end
    end

    @engine.register_action(user_id, :defend, defend_target, battle_id)
  end

  # 반격
  def counter(user_id, reply_status)
    state, battle_id = get_battle_and_state(user_id, reply_status)
    return unless state

    if state[:actions]&.key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end

    @engine.register_action(user_id, :counter, nil, battle_id)
  end

  # 물약 사용
  def use_potion(user_id, potion_size, target_id, reply_status)
    state, battle_id = get_battle_and_state(user_id, reply_status)
    return unless state

    if state[:actions]&.key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end

    user = @sheet_manager.find_user(user_id)
    unless user
      @client.reply(reply_status, "@#{user_id} 사용자 정보를 불러올 수 없습니다.")
      return
    end

    items = user["아이템"] || []
    potion_key = case potion_size
                 when "소형", "소형물약" then "소형물약"
                 when "중형", "중형물약" then "중형물약"
                 when "대형", "대형물약" then "대형물약"
                 else
                   @client.reply(reply_status, "@#{user_id} 알 수 없는 물약입니다.")
                   return
                 end

    unless items.include?(potion_key)
      @client.reply(reply_status, "@#{user_id} #{potion_key}이(가) 없습니다.")
      return
    end

    heal_target = target_id || user_id

    if %w[2v2 4v4].include?(state[:type]) && target_id
      unless same_team?(state, user_id, target_id)
        @client.reply(reply_status, "@#{user_id} 아군에게만 물약을 사용할 수 있습니다.")
        return
      end
    end

    @engine.register_action(user_id, :use_potion, heal_target, battle_id, potion_size)
  end

  private

  # 현재 전투 상태 및 ID 가져오기
  def get_battle_and_state(user_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return [nil, nil]
    end

    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    [state, battle_id]
  end

  # 같은 팀인지 확인
  def same_team?(state, user_id, target_id)
    team1 = state[:teams][:team1]
    team2 = state[:teams][:team2]
    (team1.include?(user_id) && team1.include?(target_id)) ||
      (team2.include?(user_id) && team2.include?(target_id))
  end
end

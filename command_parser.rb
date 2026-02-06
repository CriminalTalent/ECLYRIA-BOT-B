# command_parser.rb
require_relative 'commands/battle_command'
require_relative 'commands/potion_command'
require_relative 'core/battle_state'

class CommandParser
  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager

    @battle_command = BattleCommand.new(client, sheet_manager)
    @potion_command = PotionCommand.new(client, sheet_manager)

    puts "[파서] 초기화 완료"
  end

  def parse_and_execute(content, status, sender_id)
    puts "[파서] 명령어: #{content[0..100]}"

    # 전투 중 여부 캐싱
    in_battle = BattleState.find_by_participant(sender_id)

    case content
    # 우선순위 1: 물약
    when /\[물약사용\s*\/\s*(소형|중형|대형)\s*\/\s*@(\w+)\]/  # 타인 대상
      potion_size = $1
      target_id = $2
      in_battle ? @battle_command.use_potion(sender_id, potion_size, target_id, status)
                : @potion_command.use_potion_casual(sender_id, potion_size, status)

    when /\[물약사용\s*\/\s*(소형|중형|대형)\]/  # 자신 대상
      potion_size = $1
      in_battle ? @battle_command.use_potion(sender_id, potion_size, nil, status)
                : @potion_command.use_potion_casual(sender_id, potion_size, status)

    when /\[물약\s*\/\s*(소형|중형|대형)\]/  # 일상 물약
      potion_size = $1
      @potion_command.use_potion_casual(sender_id, potion_size, status)

    # 반격
    when /\[반격\]/
      @battle_command.counter(sender_id, status)

    # 방어
    when /\[방어\s*\/\s*@(\w+)\]/  # 아군 방어
      target_id = $1
      @battle_command.defend(sender_id, target_id, status)

    when /\[방어\]/  # 자기 방어
      @battle_command.defend(sender_id, nil, status)

    # 공격
    when /\[공격\s*\/\s*@(\w+)\]/  # 타겟 지정
      target_id = $1
      @battle_command.attack(sender_id, target_id, status)

    when /\[공격\]/  # 기본 공격
      @battle_command.attack(sender_id, nil, status)

    # 전투 시작
    when /\[전투\s*\/\s*@(\w+)\]/  # 1:1
      opponent_id = $1
      @battle_command.start_1v1(sender_id, opponent_id, status)

    when /\[팀전투\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\]/  # 2:2
      p1, p2, p3, p4 = $1, $2, $3, $4
      @battle_command.start_2v2(p1, p2, p3, p4, status)

    when /\[대규모전투\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\s*\/\s*@(\w+)\]/  # 4:4
      p1, p2, p3, p4, p5, p6, p7, p8 = $1, $2, $3, $4, $5, $6, $7, $8
      @battle_command.start_4v4(p1, p2, p3, p4, p5, p6, p7, p8, status)

    # 상태 확인
    when /\[체력\]|\[HP\]|\[hp\]|\[스탯\]/
      check_hp(sender_id, status)

    else
      puts "[파서] 미인식 명령어: #{content}" if content.include?('[') && content.include?(']')
    end
  rescue => e
    puts "[파서] 실행 오류: #{e.message}"
    puts e.backtrace[0..5]
    @client.reply(status, "명령어 처리 중 오류가 발생했습니다.")
  end

  private

  def check_hp(user_id, status)
    user = @sheet_manager.find_user(user_id)
    unless user
      @client.reply(status, "@#{user_id} 사용자를 찾을 수 없습니다.")
      return
    end

    name = user["이름"] || user_id
    current_hp = (user["HP"] || 0).to_i
    vitality = (user["체력"] || 10).to_i
    max_hp = 100 + (vitality * 10)
    hp_percent = (current_hp.to_f / max_hp * 100).round
    hp_bar = generate_hp_bar(current_hp, max_hp)

    message = <<~MSG
      @#{user_id}

      #{name}의 상태
      ━━━━━━━━━━━━━━━━━━
      체력: #{current_hp}/#{max_hp} (#{hp_percent}%)
      #{hp_bar}
      ━━━━━━━━━━━━━━━━━━
    MSG

    @client.reply(status, message.strip)
  end

  def generate_hp_bar(current_hp, max_hp)
    return "██████████" if current_hp >= max_hp
    return "░░░░░░░░░░" if current_hp <= 0 || max_hp <= 0

    percent = (current_hp.to_f / max_hp * 100).round
    filled = (percent / 10.0).floor
    empty = 10 - filled
    "█" * filled + "░" * empty
  end
end

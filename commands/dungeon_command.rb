# commands/dungeon_command.rb
# 공동목표 명령어 (클라리스 오르 소탕전)

require_relative '../core/dungeon_system'
require_relative '../core/dungeon_battle'

class DungeonCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @battle = DungeonBattle.new(mastodon_client, sheet_manager)
  end
  
  def handle_command(user_id, text, reply_status)
    case text
    # 공동목표 시작
    when /\[공동목표\/(B[2-5])\/((?:@\S+\/)*@\S+)\]/i
      floor = $1.upcase
      participants_text = $2
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      start_dungeon(user_id, floor, participants, false, reply_status)
      
    # 레이드 시작
    when /\[레이드\/(B[2-5])\/((?:@\S+\/)*@\S+)\]/i
      floor = $1.upcase
      participants_text = $2
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      start_dungeon(user_id, floor, participants, true, reply_status)
      
    # 맵 보기
    when /\[맵보기\]/i
      show_map(user_id, reply_status)
      
    # 상태 확인
    when /\[목표상태\]/i
      show_status(user_id, reply_status)
      
    # 이동
    when /\[이동\/(상|하|좌|우|좌상|우상|좌하|우하)\]/i
      direction = $1
      move_player(user_id, direction, reply_status)
      
    # 공격
    when /\[목표공격\]/i
      attack_enemy(user_id, reply_status)
      
    # 포기
    when /\[목표포기\]/i
      abandon_dungeon(user_id, reply_status)
      
    else
      @mastodon_client.reply(reply_status, "알 수 없는 공동목표 명령어입니다.")
    end
  end
  
  private
  
  def start_dungeon(initiator_id, floor, participants, raid_mode, reply_status)
    # 개시자 추가
    participants << initiator_id unless participants.include?(initiator_id)
    
    # 중복 제거
    participants.uniq!
    
    # 최소/최대 인원 확인
    if raid_mode
      if participants.length < 3
        @mastodon_client.reply(reply_status, "레이드는 최소 3명이 필요합니다.")
        return
      end
    else
      if participants.length < 1
        @mastodon_client.reply(reply_status, "공동목표는 최소 1명이 필요합니다.")
        return
      end
    end
    
    if participants.length > DungeonSystem::MAX_PARTICIPANTS
      @mastodon_client.reply(reply_status, "최대 #{DungeonSystem::MAX_PARTICIPANTS}명까지 참가 가능합니다.")
      return
    end
    
    # 이미 공동목표 진행 중인 플레이어 확인
    already_in = participants.find { |p| DungeonSystem.find_by_player(p) }
    if already_in
      player_name = (@sheet_manager.find_user(already_in) || {})["이름"] || already_in
      @mastodon_client.reply(reply_status, "#{player_name}님이 이미 다른 공동목표를 진행 중입니다.")
      return
    end
    
    # 공동목표 생성
    dungeon_id = DungeonSystem.create(participants, floor, raid_mode: raid_mode)
    
    unless dungeon_id
      @mastodon_client.reply(reply_status, "공동목표 생성에 실패했습니다.")
      return
    end
    
    dungeon = DungeonSystem.get(dungeon_id)
    
    # 시작 메시지
    msg = ""
    msg += "=" * 40 + "\n"
    msg += "#{raid_mode ? '레이드' : '공동목표'} 시작!\n"
    msg += "=" * 40 + "\n\n"
    msg += "장소: #{dungeon[:floor_name]}\n"
    msg += "참가자: #{participants.length}명\n"
    
    # 참가자가 10명 이하일 때만 전체 멘션
    if participants.length <= 10
      msg += participants.map { |p| "@#{p}" }.join(', ') + "\n"
    end
    
    msg += "\n"
    
    # 적 정보
    msg += "클라리스 오르 조직원 출현:\n"
    dungeon[:enemies].each do |enemy|
      msg += "- #{enemy[:name]} (HP: #{enemy[:max_hp]})\n"
    end
    
    msg += "\n" + "=" * 40 + "\n\n"
    
    # 맵
    map_text = DungeonSystem.render_map(dungeon_id)
    msg += map_text + "\n\n"
    
    msg += "명령어:\n"
    msg += "[이동/방향] - 한 칸 이동 (상/하/좌/우/대각선)\n"
    msg += "[목표공격] - 인접한 적 공격\n"
    msg += "[맵보기] - 맵 다시 보기\n"
    msg += "[목표상태] - 상태 확인\n"
    msg += "[목표포기] - 포기"
    
    # 10명 이하만 전체 멘션
    if participants.length <= 10
      @mastodon_client.reply_with_mentions(reply_status, msg, participants)
    else
      @mastodon_client.reply(reply_status, msg)
    end
  end
  
  def show_map(user_id, reply_status)
    dungeon = DungeonSystem.find_by_player(user_id)
    
    unless dungeon
      @mastodon_client.reply(reply_status, "현재 공동목표를 진행 중이지 않습니다.")
      return
    end
    
    map_text = DungeonSystem.render_map(dungeon[:dungeon_id])
    
    msg = "@#{user_id}\n"
    msg += map_text
    
    @mastodon_client.reply(reply_status, msg)
  end
  
  def show_status(user_id, reply_status)
    dungeon = DungeonSystem.find_by_player(user_id)
    
    unless dungeon
      @mastodon_client.reply(reply_status, "현재 공동목표를 진행 중이지 않습니다.")
      return
    end
    
    status = DungeonSystem.get_status(dungeon[:dungeon_id])
    
    msg = "@#{user_id}\n"
    msg += "=" * 40 + "\n"
    msg += "공동목표 상태\n"
    msg += "=" * 40 + "\n\n"
    msg += "장소: #{status[:floor]}\n"
    msg += "턴: #{status[:turn]}\n"
    msg += "참가자: #{dungeon[:total_participants]}명\n\n"
    
    msg += "플레이어 위치 (일부):\n"
    status[:players].first(5).each do |p|
      player_data = @sheet_manager.find_user(p[:id])
      player_name = player_data ? (player_data["이름"] || p[:id]) : p[:id]
      hp = player_data ? (player_data["HP"] || 0).to_i : 0
      msg += "- #{player_name} (#{p[:pos][:x]}, #{p[:pos][:y]}) HP: #{hp}\n"
    end
    
    if status[:players].length > 5
      msg += "외 #{status[:players].length - 5}명...\n"
    end
    
    msg += "\n적 상태:\n"
    status[:enemies].each do |e|
      msg += "- #{e[:name]} (#{e[:pos][:x]}, #{e[:pos][:y]}) HP: #{e[:hp]}\n"
    end
    
    msg += "\n처치한 적: #{status[:defeated]}"
    
    @mastodon_client.reply(reply_status, msg)
  end
  
  def move_player(user_id, direction, reply_status)
    dungeon = DungeonSystem.find_by_player(user_id)
    
    unless dungeon
      @mastodon_client.reply(reply_status, "현재 공동목표를 진행 중이지 않습니다.")
      return
    end
    
    result = DungeonSystem.move_player(dungeon[:dungeon_id], user_id, direction)
    
    unless result
      @mastodon_client.reply(reply_status, "이동할 수 없습니다.")
      return
    end
    
    player = @sheet_manager.find_user(user_id)
    player_name = player["이름"] || user_id
    
    msg = "@#{user_id}\n"
    msg += "#{player_name}이(가) #{direction}으로 이동했습니다.\n"
    msg += "현재 위치: (#{result[:new_pos][:x]}, #{result[:new_pos][:y]})\n"
    
    if result[:adjacent_enemy]
      enemy = dungeon[:enemies].find { |e| e[:id] == result[:adjacent_enemy] }
      if enemy
        msg += "\n적과 조우했습니다!\n"
        msg += "#{enemy[:name]} (HP: #{enemy[:hp]}/#{enemy[:max_hp]})\n"
        msg += "[목표공격]으로 공격 가능"
      end
    end
    
    @mastodon_client.reply(reply_status, msg)
  end
  
  def attack_enemy(user_id, reply_status)
    dungeon = DungeonSystem.find_by_player(user_id)
    
    unless dungeon
      @mastodon_client.reply(reply_status, "현재 공동목표를 진행 중이지 않습니다.")
      return
    end
    
    # 플레이어 위치 확인
    player_pos = nil
    dungeon[:map].each_with_index do |row, y|
      row.each_with_index do |cell, x|
        if cell && cell[:type] == 'player' && cell[:id] == user_id
          player_pos = { x: x, y: y }
          break
        end
      end
      break if player_pos
    end
    
    unless player_pos
      @mastodon_client.reply(reply_status, "위치를 찾을 수 없습니다.")
      return
    end
    
    # 인접한 적 찾기
    adjacent_enemy = find_adjacent_enemy(dungeon[:map], player_pos[:x], player_pos[:y])
    
    unless adjacent_enemy
      @mastodon_client.reply(reply_status, "인접한 적이 없습니다. 먼저 [이동]으로 적에게 다가가세요.")
      return
    end
    
    enemy = dungeon[:enemies].find { |e| e[:id] == adjacent_enemy }
    
    unless enemy
      @mastodon_client.reply(reply_status, "적을 찾을 수 없습니다.")
      return
    end
    
    # 전투 실행
    result = @battle.start_combat(dungeon[:dungeon_id], user_id, enemy[:id])
    
    msg = "@#{user_id}\n"
    msg += "=" * 40 + "\n"
    msg += @battle.format_combat_message(result)
    msg += "\n" + "=" * 40
    
    if result[:dungeon_cleared]
      msg += "\n\n모든 적을 처치했습니다!"
      msg += "\n공동목표 완료!"
      
      # 공동목표 종료
      DungeonSystem.clear(dungeon[:dungeon_id])
    end
    
    # 10명 이하만 전체 멘션, 그 이상은 공격자만
    if dungeon[:total_participants] <= 10
      @mastodon_client.reply_with_mentions(reply_status, msg, dungeon[:participants])
    else
      @mastodon_client.reply(reply_status, msg)
    end
  end
  
  def abandon_dungeon(user_id, reply_status)
    dungeon = DungeonSystem.find_by_player(user_id)
    
    unless dungeon
      @mastodon_client.reply(reply_status, "현재 공동목표를 진행 중이지 않습니다.")
      return
    end
    
    player = @sheet_manager.find_user(user_id)
    player_name = player["이름"] || user_id
    
    msg = "#{player_name}님이 공동목표를 포기했습니다.\n"
    msg += "공동목표가 종료되었습니다."
    
    # 10명 이하만 전체 멘션
    if dungeon[:total_participants] <= 10
      @mastodon_client.reply_with_mentions(reply_status, msg, dungeon[:participants])
    else
      @mastodon_client.reply(reply_status, msg)
    end
    
    DungeonSystem.clear(dungeon[:dungeon_id])
  end
  
  def find_adjacent_enemy(map, x, y)
    # 8방향 검사
    deltas = [
      [-1, -1], [0, -1], [1, -1],
      [-1,  0],          [1,  0],
      [-1,  1], [0,  1], [1,  1]
    ]
    
    deltas.each do |dx, dy|
      nx = x + dx
      ny = y + dy
      next if nx < 0 || nx > 7 || ny < 0 || ny > 7
      
      cell = map[ny][nx]
      if cell && cell[:type] == 'enemy'
        return cell[:id]
      end
    end
    
    nil
  end
end

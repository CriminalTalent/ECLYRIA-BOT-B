# core/dungeon_system_investigation.rb
# 공동목표 + 조사 시트 연동 시스템

require 'json'

class DungeonSystemInvestigation
  FLOORS = {
    'B2' => { depth: 2, name: '지하 2층', difficulty: 1, investigation_type: '조사' },
    'B3' => { depth: 3, name: '지하 3층', difficulty: 2, investigation_type: '정밀조사' },
    'B4' => { depth: 4, name: '지하 4층', difficulty: 3, investigation_type: '감지' },
    'B5' => { depth: 5, name: '지하 5층', difficulty: 4, investigation_type: '훔쳐보기' }
  }
  
  MAX_PARTICIPANTS = 30

  ENEMY_TYPES = {
    'activist' => {
      name: '순혈주의 활동가',
      hp: 40, atk: 3, def: 2, agi: 3, luck: 5, exp: 10
    },
    'supporter' => {
      name: '클라리스 지지자',
      hp: 50, atk: 4, def: 3, agi: 4, luck: 6, exp: 15
    },
    'enforcer' => {
      name: '혈통차별 집행자',
      hp: 70, atk: 5, def: 4, agi: 5, luck: 8, exp: 25
    },
    'officer' => {
      name: '클라리스 간부',
      hp: 90, atk: 6, def: 5, agi: 6, luck: 10, exp: 35
    },
    'elite' => {
      name: '정예 순혈주의자',
      hp: 120, atk: 8, def: 6, agi: 7, luck: 12, exp: 50
    },
    'commander' => {
      name: '클라리스 사령관',
      hp: 150, atk: 10, def: 8, agi: 8, luck: 15, exp: 75
    },
    'boss' => {
      name: '클라리스 오르이 핵심인물',
      hp: 300, atk: 12, def: 10, agi: 10, luck: 20, exp: 200,
      multi_attack: true, attack_count: 3
    }
  }

  @dungeons = {}
  @mutex = Mutex.new

  class << self
    attr_reader :dungeons
    
    def create(participants, floor_code, raid_mode: false, sheet_manager: nil)
      @mutex.synchronize do
        dungeon_id = generate_dungeon_id(participants, floor_code)
        
        floor_info = FLOORS[floor_code]
        return nil unless floor_info
        
        return nil if participants.length > MAX_PARTICIPANTS
        
        map = Array.new(8) { Array.new(8) { nil } }
        
        # 참가자 배치
        participants.each_with_index do |player_id, idx|
          row = idx / 8
          col = idx % 8
          y = 7 - row
          
          if y >= 0
            map[y][col] = { type: 'player', id: player_id }
          end
        end
        
        # 적 배치
        enemy_count = raid_mode ? 1 : [1, 2].sample
        enemies = []
        
        enemy_count.times do |i|
          enemy_type = select_enemy_type(floor_info[:difficulty], raid_mode)
          enemy_data = ENEMY_TYPES[enemy_type].dup
          enemy_id = "enemy_#{i+1}"
          
          loop do
            x = rand(0..7)
            y = rand(0..2)
            
            if map[y][x].nil?
              map[y][x] = { type: 'enemy', id: enemy_id }
              enemies << {
                id: enemy_id,
                type: enemy_type,
                name: enemy_data[:name],
                hp: enemy_data[:hp],
                max_hp: enemy_data[:hp],
                atk: enemy_data[:atk],
                def: enemy_data[:def],
                agi: enemy_data[:agi],
                luck: enemy_data[:luck],
                exp: enemy_data[:exp],
                position: { x: x, y: y },
                multi_attack: enemy_data[:multi_attack] || false,
                attack_count: enemy_data[:attack_count] || 1
              }
              break
            end
          end
        end
        
        @dungeons[dungeon_id] = {
          dungeon_id: dungeon_id,
          floor: floor_code,
          floor_name: floor_info[:name],
          difficulty: floor_info[:difficulty],
          investigation_type: floor_info[:investigation_type],
          raid_mode: raid_mode,
          participants: participants,
          map: map,
          enemies: enemies,
          turn: 0,
          current_player: participants.first,
          defeated_enemies: [],
          total_participants: participants.length,
          discovered_clues: {},
          sheet_manager: sheet_manager,
          created_at: Time.now
        }
        
        dungeon_id
      end
    end
    
    def get(dungeon_id)
      @mutex.synchronize do
        @dungeons[dungeon_id]
      end
    end
    
    def find_by_player(player_id)
      @mutex.synchronize do
        @dungeons.values.find { |state| state[:participants].include?(player_id) }
      end
    end
    
    def update(dungeon_id, updates)
      @mutex.synchronize do
        if @dungeons[dungeon_id]
          @dungeons[dungeon_id].merge!(updates)
        end
      end
    end
    
    def clear(dungeon_id)
      @mutex.synchronize do
        @dungeons.delete(dungeon_id)
      end
    end
    
    # 이동 + 조사 판정
    def move_player(dungeon_id, player_id, direction)
      dungeon = get(dungeon_id)
      return nil unless dungeon
      
      current_pos = find_player_position(dungeon[:map], player_id)
      return nil unless current_pos
      
      dx, dy = get_direction_delta(direction)
      new_x = current_pos[:x] + dx
      new_y = current_pos[:y] + dy
      
      return nil if new_x < 0 || new_x > 7 || new_y < 0 || new_y > 7
      return nil if dungeon[:map][new_y][new_x]
      
      # 이동 실행
      dungeon[:map][current_pos[:y]][current_pos[:x]] = nil
      dungeon[:map][new_y][new_x] = { type: 'player', id: player_id }
      
      adjacent_enemy = find_adjacent_enemy(dungeon[:map], new_x, new_y)
      
      # 조사 판정 (sheet_manager 연동)
      investigation_result = perform_investigation(dungeon, player_id, new_x, new_y)
      
      update(dungeon_id, dungeon)
      
      {
        moved: true,
        new_pos: { x: new_x, y: new_y },
        adjacent_enemy: adjacent_enemy,
        investigation: investigation_result
      }
    end
    
    # 조사 시트 연동 조사 수행
    def perform_investigation(dungeon, player_id, x, y)
      sheet_manager = dungeon[:sheet_manager]
      return nil unless sheet_manager
      
      # 이미 조사한 위치는 스킵
      location_key = "#{x},#{y}"
      return nil if dungeon[:discovered_clues][location_key]
      
      # 위치별 발견 확률
      probability = case y
                    when 0..2 then 50  # 상단 50%
                    when 3..5 then 30  # 중단 30%
                    when 6..7 then 15  # 하단 15%
                    else 0
                    end
      
      return nil if rand(100) >= probability
      
      # 조사 시트에서 해당 층의 조사 항목 가져오기
      investigation_type = dungeon[:investigation_type]
      
      # 조사 대상 찾기 (층 이름 + 조사 종류)
      target = "#{dungeon[:floor_name]} 단서"
      entry = sheet_manager.find_investigation_entry(target, investigation_type)
      
      unless entry
        # 기본 단서
        return {
          found: true,
          probability: probability,
          location: location_key,
          target: target,
          result: "이 구역에서 클라리스 오르이 조직의 흔적을 발견했습니다.",
          success: true,
          is_default: true
        }
      end
      
      # 플레이어 정보 가져오기 (행운 스탯)
      user = sheet_manager.find_user(player_id)
      luck = (user["행운"] || 10).to_i
      
      # D20 판정
      dice = rand(1..20)
      difficulty = entry["난이도"].to_i
      total = dice + luck
      success = total >= difficulty
      
      result_text = success ? entry["성공결과"] : entry["실패결과"]
      
      # 단서 기록
      clue = {
        found: true,
        probability: probability,
        location: location_key,
        target: target,
        dice: dice,
        luck: luck,
        total: total,
        difficulty: difficulty,
        success: success,
        result: result_text,
        discovered_by: player_id,
        discovered_at: Time.now
      }
      
      dungeon[:discovered_clues][location_key] = clue
      
      # 로그 기록
      sheet_manager.log_investigation(
        player_id,
        dungeon[:floor_name],
        target,
        investigation_type,
        success,
        result_text
      )
      
      clue
    end
    
    def render_map(dungeon_id)
      dungeon = get(dungeon_id)
      return nil unless dungeon
      
      map = dungeon[:map]
      lines = []
      
      lines << "#{dungeon[:floor_name]} (#{dungeon[:raid_mode] ? '레이드' : '공동목표'})"
      lines << "참가자: #{dungeon[:total_participants]}명"
      lines << "발견한 단서: #{dungeon[:discovered_clues].size}개"
      lines << "=" * 24
      lines << ""
      
      lines << "  " + (0..7).map { |x| x.to_s }.join(' ')
      
      map.each_with_index do |row, y|
        line = "#{y} "
        row.each_with_index do |cell, x|
          location_key = "#{x},#{y}"
          if dungeon[:discovered_clues][location_key]
            line += "? "  # 단서 발견한 곳
          elsif cell.nil?
            line += ". "
          elsif cell[:type] == 'player'
            line += "P "
          elsif cell[:type] == 'enemy'
            line += "E "
          end
        end
        lines << line
      end
      
      lines << ""
      lines << "P: 플레이어 | E: 적 | ?: 단서"
      lines.join("\n")
    end
    
    def get_status(dungeon_id)
      dungeon = get(dungeon_id)
      return nil unless dungeon
      
      player_positions = []
      dungeon[:participants].each do |player_id|
        pos = find_player_position(dungeon[:map], player_id)
        player_positions << { id: player_id, pos: pos }
      end
      
      enemy_positions = []
      dungeon[:enemies].each do |enemy|
        enemy_positions << {
          id: enemy[:id],
          name: enemy[:name],
          hp: "#{enemy[:hp]}/#{enemy[:max_hp]}",
          pos: enemy[:position]
        }
      end
      
      {
        floor: dungeon[:floor_name],
        turn: dungeon[:turn],
        players: player_positions,
        enemies: enemy_positions,
        defeated: dungeon[:defeated_enemies].length,
        clues_found: dungeon[:discovered_clues].size
      }
    end
    
    private
    
    def generate_dungeon_id(participants, floor_code)
      sorted = participants.sort.join('_')
      timestamp = Time.now.to_i
      "dungeon_#{floor_code}_#{sorted[0..20]}_#{timestamp}"
    end
    
    def select_enemy_type(difficulty, raid_mode)
      return 'boss' if raid_mode
      
      case difficulty
      when 1 then ['activist', 'activist', 'supporter'].sample
      when 2 then ['supporter', 'enforcer', 'enforcer'].sample
      when 3 then ['enforcer', 'officer', 'elite'].sample
      when 4 then ['officer', 'elite', 'elite', 'commander'].sample
      else 'activist'
      end
    end
    
    def find_player_position(map, player_id)
      map.each_with_index do |row, y|
        row.each_with_index do |cell, x|
          if cell && cell[:type] == 'player' && cell[:id] == player_id
            return { x: x, y: y }
          end
        end
      end
      nil
    end
    
    def find_adjacent_enemy(map, x, y)
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
    
    def get_direction_delta(direction)
      case direction.downcase
      when '상', 'w', 'up' then [0, -1]
      when '하', 's', 'down' then [0, 1]
      when '좌', 'a', 'left' then [-1, 0]
      when '우', 'd', 'right' then [1, 0]
      when '좌상', 'q' then [-1, -1]
      when '우상', 'e' then [1, -1]
      when '좌하', 'z' then [-1, 1]
      when '우하', 'c' then [1, 1]
      else [0, 0]
      end
    end
  end
end

# core/coordinate_exploration_system.rb
# 좌표 기반 탐색 + 맵 JSON 저장/로드

require 'json'
require 'time'
require 'securerandom'

module CoordinateExplorationSystem
  MAP_DATA_FILE = File.expand_path('map_data.json', __dir__)

  FLOOR_MAPS = {}
  @explorations = {}

  class << self
    attr_reader :explorations

    # ==============================
    # 맵 로드 / 저장
    # ==============================
    def load_maps!
      data =
        if File.exist?(MAP_DATA_FILE)
          raw = File.read(MAP_DATA_FILE)
          raw.strip.empty? ? default_maps : JSON.parse(raw, symbolize_names: true)
        else
          default_maps
        end

      FLOOR_MAPS.clear

      data.each do |floor_code, floor|
        floor_code_str = floor_code.to_s
        grid_hash = {}

        (floor[:grid] || {}).each do |coord, cell|
          cell_sym = (cell || {}).transform_keys(&:to_sym)
          grid_hash[coord.to_s] = {
            type:  cell_sym[:type]  || 'wall',
            name:  cell_sym[:name]  || '',
            color: cell_sym[:color] || nil
          }
        end

        FLOOR_MAPS[floor_code_str] = {
          name:               floor[:name]               || "#{floor_code_str} 층",
          difficulty:         floor[:difficulty]         || '보통',
          investigation_type: floor[:investigation_type] || '일반',
          entrance:           floor[:entrance]           || "#{floor_code_str}-A1",
          grid:               grid_hash
        }
      end

      save_maps! unless File.exist?(MAP_DATA_FILE)
    end

    def save_maps!
      data = {}

      FLOOR_MAPS.each do |code, floor|
        data[code] = {
          name:               floor[:name],
          difficulty:         floor[:difficulty],
          investigation_type: floor[:investigation_type],
          entrance:           floor[:entrance],
          grid:               floor[:grid]
        }
      end

      File.write(MAP_DATA_FILE, JSON.pretty_generate(data))
    rescue => e
      warn "[CoordinateExplorationSystem] 맵 저장 실패: #{e.class}: #{e.message}"
    end

    # 전체 층 정보 갱신 (관리자 페이지에서 저장 시 사용)
    def update_floor(floor_code, payload)
      floor_code = floor_code.to_s.upcase
      payload_sym = payload.transform_keys { |k| k.to_s }.transform_keys(&:to_sym)

      new_grid = {}
      (payload_sym[:grid] || {}).each do |coord, cell|
        cell_sym = (cell || {}).transform_keys { |k| k.to_s }.transform_keys(&:to_sym)
        new_grid[coord.to_s] = {
          type:  cell_sym[:type]  || 'wall',
          name:  cell_sym[:name]  || '',
          color: cell_sym[:color] || nil
        }
      end

      FLOOR_MAPS[floor_code] = {
        name:               payload_sym[:name]               || FLOOR_MAPS.dig(floor_code, :name)               || "#{floor_code} 층",
        difficulty:         payload_sym[:difficulty]         || FLOOR_MAPS.dig(floor_code, :difficulty)         || '보통',
        investigation_type: payload_sym[:investigation_type] || FLOOR_MAPS.dig(floor_code, :investigation_type) || '일반',
        entrance:           payload_sym[:entrance]           || FLOOR_MAPS.dig(floor_code, :entrance)           || "#{floor_code}-A1",
        grid:               new_grid
      }

      save_maps!
    end

    # 층 목록 (코드 + 이름) 반환
    def floors
      FLOOR_MAPS.map { |code, floor| { code: code, name: floor[:name] } }
    end

    # ==============================
    # 탐색 관리
    # ==============================
    def start_exploration(floor_code:, participants:, difficulty: nil, investigation_type: nil)
      floor_code = floor_code.to_s.upcase
      floor = FLOOR_MAPS[floor_code]
      raise "Unknown floor: #{floor_code}" unless floor

      id = "explore_#{floor_code}_#{Time.now.to_i}_#{SecureRandom.hex(2)}"

      @explorations[id] = {
        exploration_id:   id,
        floor:            floor_code,
        floor_name:       floor[:name],
        position:         floor[:entrance],   # 대표 위치(마지막 이동자)
        difficulty:       difficulty         || floor[:difficulty],
        investigation_type: investigation_type || floor[:investigation_type],
        participants:     participants || [],
        discovered_clues: [],
        found_items:      [],
        defeated_enemies: [],
        current_encounter: nil,
        deep_investigation: nil,
        active:           true,
        created_at:       Time.now,
        player_positions: {}                 # "acct" => "B3-C4"
      }

      @explorations[id]
    end

    def get(exploration_id)
      @explorations[exploration_id]
    end

    # 플레이어 개별 위치 업데이트
    def update_position(exploration_id, player_acct, coord)
      exp = @explorations[exploration_id]
      return unless exp

      exp[:player_positions] ||= {}
      exp[:player_positions][player_acct] = coord
      exp[:position] = coord # 대표 위치를 마지막 이동자로 맞춤
      exp
    end

    # 탐색 종료
    def end_exploration(exploration_id)
      exp = @explorations[exploration_id]
      return unless exp
      exp[:active] = false
      exp
    end

    private

    # JSON이 없을 때 기본 구조 (비어있는 8x8 맵)
    def default_maps
      base_floor = lambda do |code|
        {
          name:               "#{code} 층",
          difficulty:         "보통",
          investigation_type: "일반",
          entrance:           "#{code}-D8",
          grid:               default_grid(code)
        }
      end

      {
        "B2" => base_floor.call("B2"),
        "B3" => base_floor.call("B3"),
        "B4" => base_floor.call("B4"),
        "B5" => base_floor.call("B5")
      }
    end

    # 전체를 wall로 채운 8x8 기본 그리드
    def default_grid(floor_code)
      grid = {}
      cols = %w[A B C D E F G H]
      (1..8).each do |row|
        cols.each do |col|
          coord = "#{floor_code}-#{col}#{row}"
          grid[coord] = { type: 'wall', name: '', color: nil }
        end
      end
      grid
    end
  end

  # 파일 require 시 자동 로드
  load_maps!
end

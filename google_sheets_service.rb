# google_sheets_service.rb
# SheetManager를 활용한 Google Sheets 서비스

require_relative 'sheet_manager'

class GoogleSheetsService
  def initialize(sheet_id, credentials_path)
    @sheet_manager = SheetManager.new(sheet_id, credentials_path)
  end

  # 탐색 데이터 가져오기
  def get_exploration_data(exploration_id)
    # 조사상태 시트에서 활성 탐색 찾기
    # (실제로는 CoordinateExplorationSystem의 메모리에 있지만,
    #  Google Sheets에서 위치 정보를 가져올 수 있음)
    {
      exploration_id: exploration_id,
      participants: [],
      floor: 'B3',
      current_position: 'B3-D8',
      discovered_clues: [],
      found_items: [],
      defeated_enemies: []
    }
  end

  # 플레이어 위치 가져오기 (조사상태 시트에서)
  def get_player_positions
    rows = @sheet_manager.read_values("조사상태!A:Z")
    return [] unless rows && rows.length > 1

    headers = rows[0]
    location_col = headers.index("위치")
    return [] unless location_col

    positions = []
    rows.each_with_index do |row, idx|
      next if idx == 0  # 헤더 스킵
      next unless row[0] && row[location_col]  # ID와 위치가 있어야 함
      
      positions << {
        user_id: row[0].gsub('@', ''),
        position: row[location_col],
        floor: extract_floor_from_position(row[location_col])
      }
    end

    positions
  rescue => e
    puts "[에러] get_player_positions: #{e.message}"
    []
  end

  # 전체 탐색 목록
  def get_all_explorations
    # 메모리 기반이므로 CoordinateExplorationSystem에서 관리
    []
  end

  private

  # 좌표에서 층 추출 (예: "B3-D8" → "B3")
  def extract_floor_from_position(position)
    return nil unless position
    position.to_s.split('-').first
  end
end

# google_sheets_service.rb
# SheetManager를 활용한 Google Sheets 서비스

require_relative 'sheet_manager'

class GoogleSheetsService
  def initialize(sheet_id = nil, credentials_path = nil)
    if sheet_id && credentials_path && File.exist?(credentials_path)
      @sheet_manager = SheetManager.new(sheet_id, credentials_path)
      puts "[GoogleSheetsService] Google Sheets 연동 활성화"
    else
      @sheet_manager = nil
      puts "[GoogleSheetsService] 테스트 모드"
    end
  end

  # 탐색 데이터 가져오기
  def get_exploration_data(exploration_id)
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
    return [] unless @sheet_manager
    
    rows = @sheet_manager.read_values("조사상태!A:Z")
    return [] unless rows && rows.length > 1

    headers = rows[0]
    location_col = headers.index("위치")
    return [] unless location_col

    positions = []
    rows.each_with_index do |row, idx|
      next if idx == 0
      next unless row[0] && row[location_col]
      
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
    []
  end

  private

  # 좌표에서 층 추출 (예: "B3-D8" → "B3")
  def extract_floor_from_position(position)
    return nil unless position
    position.to_s.split('-').first
  end
end

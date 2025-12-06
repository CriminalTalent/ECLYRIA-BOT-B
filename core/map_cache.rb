require 'json'

class MapCache
  FILE_PATH = File.expand_path("map_data.json", __dir__)
  
  def self.load
    return initialize_default_map unless File.exist?(FILE_PATH)
    
    begin
      JSON.parse(File.read(FILE_PATH))
    rescue JSON::ParserError => e
      puts "⚠️  맵 데이터 파싱 실패: #{e.message}"
      initialize_default_map
    rescue => e
      puts "⚠️  맵 데이터 로드 실패: #{e.message}"
      initialize_default_map
    end
  end
  
  def self.save(data)
    File.write(FILE_PATH, JSON.pretty_generate(data))
    true
  rescue => e
    puts "⚠️  맵 데이터 저장 실패: #{e.message}"
    false
  end
  
  private
  
  def self.initialize_default_map
    {
      "B2" => {
        "name" => "지하 2층",
        "difficulty" => "쉬움",
        "investigation_type" => "조사",
        "entrance" => "B2-D8",
        "grid" => {}
      },
      "B3" => {
        "name" => "마법 도서관 / B3층",
        "difficulty" => "보통",
        "investigation_type" => "정밀조사",
        "entrance" => "B3-D8",
        "grid" => {}
      },
      "B4" => {
        "name" => "지하 4층",
        "difficulty" => "어려움",
        "investigation_type" => "감지",
        "entrance" => "B4-D8",
        "grid" => {}
      },
      "B5" => {
        "name" => "지하 5층",
        "difficulty" => "매우 어려움",
        "investigation_type" => "훔쳐보기",
        "entrance" => "B5-D8",
        "grid" => {}
      }
    }
  end
end

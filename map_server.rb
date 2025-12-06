require 'sinatra'
require 'json'
require_relative 'google_sheets_service'
require_relative 'map_cache'

set :bind, '0.0.0.0'
set :port, 4567
set :public_folder, File.dirname(__FILE__) + '/public'

service = GoogleSheetsService.new

before do
  headers 'Access-Control-Allow-Origin' => '*'
end

# 위치 가져오기 (플레이어)
get '/api/players' do
  content_type :json
  { success: true, players: service.load_locations }.to_json
end

# 타일 세부 조사 정보
get '/api/tile/:name' do
  content_type :json
  name = params[:name]
  details = service.load_explore_details.find { |e| e[:name] == name }
  
  if details
    { success: true, tile: details }.to_json
  else
    { success: false, error: "Tile '#{name}' not found" }.to_json
  end
end

# 전체 맵 JSON (새 구조 반영)
get '/api/map-json/:floor' do
  content_type :json
  data = MapCache.load
  floor = params[:floor]
  
  if data[floor]
    { success: true, floor: data[floor] }.to_json
  else
    { success: false, error: "Floor '#{floor}' not found" }.to_json
  end
end

# 모든 층 목록
get '/api/floors' do
  content_type :json
  data = MapCache.load
  floors = data.keys.map do |floor_code|
    {
      code: floor_code,
      name: data[floor_code]["name"],
      difficulty: data[floor_code]["difficulty"],
      investigation_type: data[floor_code]["investigation_type"]
    }
  end
  { success: true, floors: floors }.to_json
end

# 관리자 저장 API
post '/api/admin/save-map' do
  content_type :json
  
  begin
    new_data = JSON.parse(request.body.read)
    MapCache.save(new_data)
    { success: true, message: "맵 데이터 저장 완료" }.to_json
  rescue JSON::ParserError => e
    status 400
    { success: false, error: "Invalid JSON: #{e.message}" }.to_json
  rescue => e
    status 500
    { success: false, error: "Save failed: #{e.message}" }.to_json
  end
end

# 관리자 대시보드
get '/admin' do
  send_file File.join(settings.public_folder, 'admin_dashboard.html')
end

# 실시간 맵
get '/map' do
  send_file File.join(settings.public_folder, 'realtime_map.html')
end

# 층별 맵 (쿼리 파라미터)
get '/map/:floor' do
  send_file File.join(settings.public_folder, 'realtime_map.html')
end

# 루트 - 맵으로 리다이렉트
get '/' do
  redirect '/map'
end

# 서버 상태 체크
get '/api/health' do
  content_type :json
  { 
    success: true, 
    status: "online",
    timestamp: Time.now.to_i,
    floors_count: MapCache.load.keys.size
  }.to_json
end

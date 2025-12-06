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
    { success: false }.to_json
  end
end

# 전체 맵 JSON
get '/api/map-json/:floor' do
  content_type :json
  data = MapCache.load
  floor = params[:floor]

  if data["floors"][floor]
    { success: true, floor: data["floors"][floor] }.to_json
  else
    { success: false }.to_json
  end
end

# 관리자 저장 API
post '/api/admin/save-map' do
  content_type :json
  new_data = JSON.parse(request.body.read)
  MapCache.save(new_data)
  { success: true }.to_json
end

get '/admin' do
  send_file File.join(settings.public_folder, 'admin_dashboard.html')
end

get '/map' do
  send_file File.join(settings.public_folder, 'realtime_map.html')
end

get '/' do
  redirect '/map'
end

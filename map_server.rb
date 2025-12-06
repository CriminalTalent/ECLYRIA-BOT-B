# map_server.rb
# 실시간 맵 서버

require 'sinatra'
require 'json'
require_relative 'core/coordinate_exploration_system'

# 서버 설정
set :bind, '0.0.0.0'
set :port, 4567
set :public_folder, File.dirname(__FILE__) + '/public'

# CORS 설정 (필요시)
before do
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => ['GET', 'POST'],
          'Access-Control-Allow-Headers' => 'Content-Type'
end

# 헬스체크
get '/health' do
  content_type :json
  { status: 'ok', timestamp: Time.now.to_i }.to_json
end

# 탐색 정보 API
get '/api/exploration/:exploration_id' do
  content_type :json
  
  exploration = CoordinateExplorationSystem.get(params[:exploration_id])
  
  if exploration
    {
      success: true,
      exploration: {
        id: exploration[:exploration_id],
        floor: exploration[:floor],
        floor_name: exploration[:floor_name],
        position: exploration[:position],
        difficulty: exploration[:difficulty],
        investigation_type: exploration[:investigation_type],
        participants: exploration[:participants],
        discovered_clues: exploration[:discovered_clues].size,
        found_items: exploration[:found_items].size,
        defeated_enemies: exploration[:defeated_enemies].size,
        current_encounter: exploration[:current_encounter],
        deep_investigation: exploration[:deep_investigation],
        active: exploration[:active],
        created_at: exploration[:created_at]
      }
    }.to_json
  else
    status 404
    { success: false, error: 'Exploration not found' }.to_json
  end
end

# 모든 활성 탐색 목록
get '/api/explorations' do
  content_type :json
  
  active_explorations = CoordinateExplorationSystem.explorations.values.select { |e| e[:active] }
  
  {
    success: true,
    count: active_explorations.size,
    explorations: active_explorations.map { |e|
      {
        id: e[:exploration_id],
        floor: e[:floor],
        floor_name: e[:floor_name],
        position: e[:position],
        participants: e[:participants],
        created_at: e[:created_at]
      }
    }
  }.to_json
end

# 맵 데이터 API
get '/api/map/:floor' do
  content_type :json
  
  floor_code = params[:floor].upcase
  map_info = CoordinateExplorationSystem::FLOOR_MAPS[floor_code]
  
  if map_info
    {
      success: true,
      floor: floor_code,
      name: map_info[:name],
      difficulty: map_info[:difficulty],
      investigation_type: map_info[:investigation_type],
      entrance: map_info[:entrance],
      grid: map_info[:grid]
    }.to_json
  else
    status 404
    { success: false, error: 'Floor not found' }.to_json
  end
end

# 실시간 맵 페이지
get '/map' do
  send_file File.join(settings.public_folder, 'realtime_map.html')
end

# 루트 페이지
get '/' do
  content_type :html
  <<~HTML
    <!DOCTYPE html>
    <html lang="ko">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>맵 서버</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: #1a1a1a;
                color: #fff;
                padding: 40px;
                margin: 0;
            }
            .container {
                max-width: 800px;
                margin: 0 auto;
            }
            h1 {
                color: #ff6b6b;
                text-align: center;
                text-shadow: 0 0 10px rgba(255, 107, 107, 0.5);
            }
            .card {
                background: #2a2a2a;
                border-radius: 10px;
                padding: 30px;
                margin: 20px 0;
                box-shadow: 0 4px 6px rgba(0,0,0,0.3);
            }
            .card h2 {
                color: #4a9eff;
                margin-bottom: 15px;
            }
            .api-list {
                list-style: none;
                padding: 0;
            }
            .api-list li {
                background: #333;
                padding: 15px;
                margin: 10px 0;
                border-radius: 5px;
                border-left: 4px solid #6bcf7f;
            }
            .api-list code {
                color: #9f9;
                font-family: 'Courier New', monospace;
            }
            .status {
                display: inline-block;
                padding: 5px 15px;
                background: #6bcf7f;
                color: #1a1a1a;
                border-radius: 20px;
                font-weight: bold;
            }
            a {
                color: #4a9eff;
                text-decoration: none;
            }
            a:hover {
                text-decoration: underline;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>맵 서버</h1>
            
            <div class="card">
                <h2>서버 상태</h2>
                <p><span class="status">온라인</span></p>
                <p>서버 시간: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}</p>
            </div>
            
            <div class="card">
                <h2>📡 API 엔드포인트</h2>
                <ul class="api-list">
                    <li>
                        <code>GET /health</code><br>
                        서버 헬스체크
                    </li>
                    <li>
                        <code>GET /api/exploration/:exploration_id</code><br>
                        특정 탐색 정보 조회
                    </li>
                    <li>
                        <code>GET /api/explorations</code><br>
                        모든 활성 탐색 목록
                    </li>
                    <li>
                        <code>GET /api/map/:floor</code><br>
                        층별 맵 데이터 (B2, B3, B4, B5)
                    </li>
                </ul>
            </div>
            
            <div class="card">
                <h2>실시간 맵</h2>
                <p>탐색 시작 시 봇이 제공하는 링크를 클릭하세요.</p>
                <p>예시: <code>/map?id=explore_B3_123456</code></p>
                <p><a href="/map">맵 페이지 열기</a></p>
            </div>
            
            <div class="card">
                <h2>통계</h2>
                <p>활성 탐색: <strong>#{CoordinateExplorationSystem.explorations.values.count { |e| e[:active] }}</strong>개</p>
                <p>전체 탐색: <strong>#{CoordinateExplorationSystem.explorations.size}</strong>개</p>
            </div>
        </div>
    </body>
    </html>
  HTML
end

# 에러 핸들링
error do
  content_type :json
  { success: false, error: env['sinatra.error'].message }.to_json
end

not_found do
  content_type :json
  { success: false, error: 'Not found' }.to_json
end

# 서버 시작 로그
if __FILE__ == $0
  puts "=" * 50
  puts "맵 서버 시작"
  puts "=" * 50
  puts "포트: #{settings.port}"
  puts "바인드: #{settings.bind}"
  puts "시간: #{Time.now}"
  puts "=" * 50
end

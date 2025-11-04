# /root/mastodon_bots/battle_bot/scripts/reset_move_points.rb
require 'google/apis/sheets_v4'
require 'googleauth'
require '/root/mastodon_bots/sheet_manager.rb'  # ✅ 확장자 포함 + 절대 경로
require 'time'

# === 환경설정 ===
TIMEZONE = 'Asia/Seoul'
RESET_POINTS = 3

# === 시트 ID와 인증 경로 지정 ===
SHEET_ID = '1sf6DpuOZXpLVMc8EwJr_gzsUOx_GO2Tp3mgsIQZtkOQ'  # ✅ 실제 시트 ID
CREDENTIALS_PATH = '/root/mastodon_bots/credentials.json'  # ✅ 서비스 계정 키 경로

sheet_manager = SheetManager.new(SHEET_ID, CREDENTIALS_PATH)

now = Time.now.getlocal('+09:00')
puts "[#{now.strftime('%Y-%m-%d %H:%M:%S')}] 이동 포인트 초기화 실행"

rows = sheet_manager.read_values('조사상태!A:F')
rows&.each_with_index do |row, i|
  next if i == 0 || row[0].to_s.strip.empty?
  # ⚠️ F열이 '이동포인트' 컬럼이라고 가정
  sheet_manager.update_values("조사상태!F#{i + 1}", [[RESET_POINTS]])
end

puts "모든 사용자 이동 포인트가 #{RESET_POINTS}로 초기화되었습니다."

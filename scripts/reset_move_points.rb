# scripts/reset_move_points.rb
require_relative '../utils/sheet_manager'

# === 환경설정 ===
TIMEZONE = 'Asia/Seoul'
RESET_POINTS = 3

sheet_manager = SheetManager.new
now = Time.now.getlocal('+09:00')
puts "[#{now.strftime('%Y-%m-%d %H:%M:%S')}] 이동 포인트 초기화 실행"

rows = sheet_manager.read_values('조사상태!A:F')
rows.each_with_index do |row, i|
  next if i == 0 || row[0].to_s.strip.empty?
  user_id = row[0]
  sheet_manager.update_move_points(user_id, RESET_POINTS)
end

puts "모든 사용자 이동 포인트가 #{RESET_POINTS}로 초기화되었습니다."

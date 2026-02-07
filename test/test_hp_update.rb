require 'bundler/setup'
require 'dotenv/load'
require_relative '../sheet_manager'

puts "HP 업데이트 테스트"

# Initialize SheetManager
sheet_manager = SheetManager.new
test_user_id = ARGV[0]

unless test_user_id
  puts "\n사용법: ruby test_hp_update.rb <사용자ID>"
  puts "예시: ruby test_hp_update.rb Test_1"
  exit 1
end

puts "\n[1] 현재 사용자 정보 조회: #{test_user_id}"
user = sheet_manager.find_user(test_user_id)

unless user
  puts "사용자를 찾을 수 없습니다: #{test_user_id}"
  exit 1
end

puts "  - 이름: #{user['이름']}"
puts "  - HP: #{user['HP']}"
puts "  - 공격: #{user['공격']}"
puts "  - 방어: #{user['방어']}"
puts "  - 아이템: #{user['아이템']}"

original_hp = user['HP'].to_i

puts "\n[2] HP 업데이트 테스트 (HP -10)"
new_hp = original_hp - 10
result = sheet_manager.update_user(test_user_id, { "HP" => new_hp })
puts "  - update_user 결과: #{result}"

puts "\n[3] 업데이트 후 사용자 정보 재조회"
sheet_manager.invalidate_cache
user_after = sheet_manager.find_user(test_user_id)

if user_after
  puts "  - HP (변경 전): #{original_hp}"
  puts "  - HP (변경 후): #{user_after['HP']}"

  if user_after['HP'].to_i == new_hp
    puts "\n✓ HP 업데이트 성공!"
  else
    puts "\n✗ HP 업데이트 실패 - 값이 변경되지 않음"
  end
else
  puts "  사용자 재조회 실패"
end

puts "\n[4] HP 원복 (#{original_hp})"
sheet_manager.update_user(test_user_id, { "HP" => original_hp })
sheet_manager.invalidate_cache
user_restored = sheet_manager.find_user(test_user_id)
puts "  - HP 원복 결과: #{user_restored['HP']}"
puts "테스트 완료"

# commands/potion_command.rb

require_relative '../core/sheet_manager'

class PotionCommand
  def initialize(masto, sheet)
    @masto = masto
    @sheet = sheet
  end

  def handle(status)
    user_id = status[:account][:acct]
    inventory = SheetManager.get_stat(user_id, "아이템")
    return unless inventory

    potion_line = inventory.split(',').find { |i| i.include?("포션") }
    unless potion_line
      @masto.say("@#{user_id}는 포션을 가지고 있지 않습니다.")
      return
    end

    count = potion_line.match(/포션(\d+)/)&. &.to_i || 0
    if count <= 0
      @masto.say("@#{user_id}는 포션이 없습니다.")
      return
    end

    # 랜덤 회복량
    amount = [5, 10, 15, 20].sample
    hp = SheetManager.get_stat(user_id, "체력").to_i
    new_hp = [hp + amount, 100].min
    SheetManager.set_stat(user_id, "체력", new_hp)

    # 포션 차감
    new_inventory = inventory.gsub(/포션:\d+/) { "포션:#{count - 1}" }
    SheetManager.set_stat(user_id, "아이템", new_inventory)

    @masto.say("@#{user_id}의 체력이 #{amount} 회복되었습니다. 현재 체력 #{new_hp}")
  end
end

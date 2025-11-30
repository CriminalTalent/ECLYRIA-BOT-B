# command_parser.rb
# encoding: UTF-8

require_relative 'commands/battle_command'

class CommandParser
  def initialize(mastodon, sheet_manager, engine)
    @mastodon = mastodon
    @sheet_manager = sheet_manager
    @engine = engine
    log("CommandParser 초기화 완료")
  end

  def log(msg)
    puts "[CommandParser] #{msg}"
  end

  # ================================
  #   Mentions 파싱
  # ================================
  def handle(status)
    return unless status['visibility'] == 'direct' || status['mentions'].any?

    content = clean(status['content'])
    user = status['account']['acct']

    log("handle(): #{user}: #{content}")

    if content =~ /\[전투개시\/?@?([A-Za-z0-9_]+)\/?@?([A-Za-z0-9_]+)\]/ ||
       content =~ /\[전투\s*@?([A-Za-z0-9_]+)\s*vs\s*@?([A-Za-z0-9_]+)\]/
      p1 = $1
      p2 = $2
      reply(status, @engine.start_1v1(p1, p2))
      return
    end

    if content =~ /^\[공격\]/
      reply(status, @engine.attack(user))
      return
    end

    if content =~ /^\[방어\]/
      reply(status, @engine.defend(user))
      return
    end

    if content =~ /^\[도망\]/
      reply(status, @engine.flee(user))
      return
    end

    if content =~ /^\[전투상태\]/
      reply(status, @engine.status(user))
      return
    end
  rescue => e
    log("Error in handle(): #{e.class} - #{e.message}")
    reply(status, "⚠ 처리 중 오류가 발생했습니다.")
  end

  private

  def reply(status, text)
    @mastodon.reply_with_mentions(
      status_id: status['id'],
      message: text,
      visibility: "direct"
    )
  end

  def clean(html)
    html.gsub(/<[^>]*>/, '').strip
  end
end

# command_parser.rb
# 인코딩: UTF-8

class CommandParser
  # 전투봇이 처리할 명령어 패턴들
  PATTERNS = [
    /\[(?:전투|1v1)\s+@?\S+\s+vs\s+@?\S+\]/i,         # [전투 @A vs @B]
    /\[다인전투\/@?\S+\/@?\S+\/@?\S+\/@?\S+\]/i,     # [다인전투/@A/@B/@C/@D]
    /\[공격(?:\/@?\S+)?\]/i,                         # [공격] / [공격/@A]
    /\[방어(?:\/@?\S+)?\]/i,                         # [방어] / [방어/@A]
    /\[반격\]/i,
    /\[도주\]/i,
    /\[허수아비\s*(하|중|상)\]/i                      # [허수아비 하/중/상]
  ].freeze

  def parse(text)
    normalized = normalize_text(text)

    return nil unless match_command?(normalized)

    normalized
  end

  private

  # 텍스트에서 제어문자 제거 → 공백/이모지에도 견고하게
  def normalize_text(text)
    text.to_s.gsub(/\p{Cf}/, '').strip
  end

  # 한 패턴이라도 일치하면 실행
  def match_command?(text)
    PATTERNS.any? { |pattern| text.match?(pattern) }
  end
end

# http_patch.rb
# HTTP gem의 응답 파싱 문제 해결

require 'http'

module HTTP
  class Response
    class Parser
      # nil 체크 추가
      def read(size)
        return nil if size.nil? || size < 0
        
        begin
          @parser.read(size)
        rescue => e
          puts "[HTTP Parser Error] #{e.message}"
          nil
        end
      end
    end

    class Body
      # Completely override readpartial to avoid frozen strings and nil issues
      def readpartial(size = nil)
        return unless @stream
        
        # size가 nil이면 기본값 사용
        size = 16384 if size.nil?
        
        chunk = @stream.readpartial(size)
        return nil unless chunk
        
        # Force unfrozen string
        String.new(chunk.to_s, encoding: encoding)
      rescue EOFError
        nil
      rescue => e
        puts "[HTTP Body Error] #{e.message}"
        nil
      end

      # Override to_s
      def to_s
        return @cached_string if defined?(@cached_string)
        
        result = String.new
        loop do
          chunk = readpartial
          break unless chunk
          result << chunk
        end
        
        @cached_string = result
        result
      rescue => e
        puts "[HTTP to_s Error] #{e.message}"
        ""
      end
    end
  end
end

puts "[HTTP Patch] 응답 파싱 패치 적용 완료"

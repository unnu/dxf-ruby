module DXF
  class Data
    attr_reader :data

    def initialize
      @data = {}
      @marker = nil
      @data[@marker] = []
    end

    def push(code, value)
      code = code.to_i
      if code == 100
        @marker = value
        @data[@marker] ||= []
      else
        @data[@marker] << [code, value]
      end
    end

    def serialize
      stream = []
      @data.each do |marker, sub_data|
        stream << [100, marker] if marker
        stream.concat(sub_data)
      end
      stream
    end

    def change(marker, code, value)
      sub_data = @data[marker] ||= []
      pair = sub_data.find {|pair| pair.first == code}
      if pair
        pair[1] = value
      else
        @data[marker] << [code, value] if value
      end
    end

    def inspect
      "#<#{self.class.inspect}:#{object_id}>"
    end
  end
end

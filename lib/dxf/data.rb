module DXF
  class Data

    def initialize
      @data = {}
      @marker = nil
    end

    def push(code, value)
      code = code.to_i
      if code == 100
        @marker = value
      end
      (@data[@marker] ||= []) << [code, value]
    end

    def serialize
      stream = []
      @data.values.each do |sub_data|
        stream.concat(sub_data)
      end
      stream
    end

    def change_single(marker, code, value)
      sub_data = @data[marker] ||= []
      pair = sub_data.find {|pair| pair.first == code}
      if pair
        pair[1] = value
      else
        @data[marker] << [code, value]
      end
    end

    def inspect
      "#<#{self.class.inspect}:#{object_id}>"
    end
  end
end

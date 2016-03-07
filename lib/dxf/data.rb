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
      sub_data = sub_data(marker)

      in_array = false
      index = nil
      sub_data.each.with_index do |(_code, _), i|
        if _code == 102
          in_array = !in_array
        else
          if _code == code && !in_array
            index = i
            break
          end
        end
      end
      index ||= sub_data.size

      if value
        sub_data[index] = [code, value]
      else
        sub_data.delete_at(index)
      end
    end

    def change_array(marker, code, values, array_code, array_name = nil)
      sub_data = sub_data(marker)

      array_start = sub_data.index {|(_code, _value)| _code == array_code }

      if array_start
        array_end = sub_data.rindex {|(_code, _value)| _code == array_code }
      else
        array_start = array_end = sub_data.size
      end

      if values.empty?
        sub_data.slice!(array_start..array_end)
      else
        array = []
        array << [array_code, "{#{array_name}"]
        array.concat(values.map {|value| [code, value] })
        array << [array_code, '}']

        sub_data[array_start..array_end] = array
      end
    end

    def inspect
      "#<#{self.class.inspect}:#{object_id}>"
    end

    private

    def sub_data(marker)
      @data[marker] ||= []
    end
  end
end

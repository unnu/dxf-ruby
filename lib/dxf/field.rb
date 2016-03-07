module DXF
  class Field
    attr_accessor :marker
    attr_accessor :code
    attr_accessor :name
    attr_accessor :default
    attr_accessor :serializer
    attr_accessor :deserializer
    attr_accessor :array_code
    attr_accessor :array_name

    def initialize(marker, code, name, default: nil, serializer: nil, deserializer: nil, array_code: nil, array_name: nil)
      @marker = marker
      @code = code
      @name = name
      @default = default
      @serializer = serializer || Proc.new {|object| object.send(name) }
      @deserializer = deserializer || Proc.new {|object, value| value }
      @array_code = array_code
      @array_name = array_name
    end

    def serialize(object, data)
      if @array_code
        data.change_array(@marker, @code, @serializer.call(object), @array_code, @array_name)
      else
        data.change(@marker, @code, @serializer.call(object))
      end
    end

    def deserialize(object, value)
      if @array_code
        array = object.public_send(@name) || []
        array << @deserializer.call(object, value)
        object.public_send("#{@name}=", array)
      else
        object.public_send("#{@name}=", @deserializer.call(object, value))
      end
    end
  end
end

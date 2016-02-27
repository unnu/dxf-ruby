module DXF
  class Field
    attr_accessor :marker
    attr_accessor :code
    attr_accessor :name
    attr_accessor :default
    attr_accessor :serializer
    attr_accessor :deserializer

    def initialize(marker, code, name, default: nil, serializer: nil, deserializer: nil)
      @marker = marker
      @code = code
      @name = name
      @default = default
      @serializer = serializer || Proc.new {|object| object.send(name) }
      @deserializer = deserializer || Proc.new {|object, value| value }
    end

    def serialize(object, data)
      data.change(marker, code, @serializer.call(object))
    end

    def deserialize(object, value)
      object.public_send("#{name}=", @deserializer.call(object, value))
    end
  end
end

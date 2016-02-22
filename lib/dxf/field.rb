module DXF
  class Field
    attr_accessor :marker
    attr_accessor :code
    attr_accessor :name
    attr_accessor :serializer
    attr_accessor :deserializer

    def initialize(marker, code, name, serializer, deserializer)
      @marker = marker
      @code = code
      @name = name
      @serializer = serializer || Proc.new {|object, data| data.change(marker, code, object.send(name)) }
      @deserializer = deserializer || Proc.new {|object, value| object.send("#{name}=", value) }
    end

    def deserialize(object, value)
      @deserializer.call(object, value)
    end

    def serialize(object, data)
      @serializer.call(object, data)
    end
  end
end

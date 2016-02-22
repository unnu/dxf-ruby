require 'geometry'
require_relative 'serializer'

module DXF
  class Variable
    include Serializer

    attr_accessor :name
    attr_accessor :value
    attr_accessor :code

    def initialize(name)
      @name = name
    end

    def parse_pair(code, value)
      case code.to_i
      when 10 then
        self.value = Geometry::Point[value]
      when 20 then
        self.value = Geometry::Point[self.value.x, value]
      when 30 then
        self.value = Geometry::Point[self.value.x, self.value.y, value]
      else
        self.code  = code.to_i
        self.value = value
      end
    end

    def serialize
      data = []
      data << [9, name]
      if is_point?
        Serializer.point(value).each {|c| data << c }
      else
        data << [code, value]
      end
      data
    end

    def is_point?
      value.is_a?(Geometry::Point)
    end
  end
end

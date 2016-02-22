module DXF
  module Serializer
    extend self

    def point(point)
      data = []
      data << [10, point.x]
      data << [20, point.y]
      data << [30, point.z] if point.z
      data
    end
  end
end

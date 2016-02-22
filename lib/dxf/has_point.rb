module DXF
  module HasPoint
    def self.included(base)
      base.class_eval do
        field 10, :x
        field 20, :y
        field 30, :z
      end
    end

    def point
      coordinates = [x, y, z].compact
      if coordinates.empty?
        Geometry::Point.zero
      else
        Geometry::Point[coordinates]
      end
    end

    def distance(other)
      return unless other

      xd = x - other.x
      yd = y - other.y
      zd = z - other.z
      Math.sqrt(xd * xd + yd * yd + zd * zd)
    end
  end
end

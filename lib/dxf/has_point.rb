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

    def point=(point)
      self.x = point.x
      self.y = point.y
      self.z = point.z
    end

    def distance(other)
      return unless other

      xd = x - other.x
      yd = y - other.y
      zd = z - other.z
      Math.sqrt(xd * xd + yd * yd + zd * zd)
    end

    def move(x: nil, y: nil, z: nil)
      self.x += x if x
      self.y += y if y
      self.z += z if z
      self
    end
  end

  module HasPoint2
    def self.included(base)
      base.class_eval do
        field 11, :x2
        field 21, :y2
        field 31, :z2
      end
    end

    def point2
      coordinates = [x2, y2, z2].compact
      if coordinates.empty?
        Geometry::Point.zero
      else
        Geometry::Point[coordinates]
      end
    end

    def point2=(point)
      self.x2 = point.x
      self.y2 = point.y
      self.z2 = point.z
    end

    def distance2(point)
      xd = x2 - other.x
      yd = y2 - other.y
      zd = z2 - other.z
      Math.sqrt(xd * xd + yd * yd + zd * zd)
    end

    def move2(x: nil, y: nil, z: nil)
      self.x2 += x if x
      self.y2 += y if y
      self.z2 += z if z
      self
    end
  end
end

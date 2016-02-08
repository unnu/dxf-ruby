require 'geometry'

require_relative 'cluster_factory'

module DXF
  # {Entity} is the base class for everything that can live in the ENTITIES block
  class Entity
    TypeError = Class.new(StandardError)

    include ClusterFactory

    attr_accessor :x, :y, :z

    attr_accessor :type
    attr_accessor :parser
    attr_accessor :data

    attr_accessor :color
    attr_accessor :handle
    attr_accessor :name
    attr_accessor :layer
    attr_accessor :line_type
    attr_accessor :line_weight
    attr_accessor :soft_pointer
    attr_accessor :owner
    attr_accessor :subclass_marker
    attr_accessor :ext_data
    attr_accessor :ext_app_name

    def self.new(type, parser)
      entity = case type
      when 'CIRCLE' then Circle.new
      when 'LINE' then Line.new
      when 'POINT' then Point.new
      when 'SPLINE' then Spline.new
      when 'TEXT' then Text.new
      when 'MTEXT' then MText.new
      when 'ATTRIB' then Attribute.new
      when 'INSERT' then Insert.new
      when 'BLOCK' then Block.new
      when 'BLOCK_RECORD' then BlockRecord.new
      else
        super()
        # raise TypeError, "Unrecognized entity type '#{type}'"
      end

      entity.type = type
      entity.parser = parser
      entity.data = []
      entity
    end

    def parse_pair(code, value)
      self.data << [code, value]
      # Handle group codes that are common to all entities
      # These are from the table that starts on page 70 of specification
      case code.to_i
      when 2
        self.name = value
      when 5
        self.handle = value
      when 6
        self.line_type = value
      when 8
        self.layer = value
      when 10 then
        self.x = value.to_f
      when 20 then
        self.y = value.to_f
      when 30 then
        self.z = value.to_f
      when 62
        self.color = value.to_i
      when 100
        self.subclass_marker = value
      when 330..339
        self.soft_pointer = value
      when 360
        self.owner = value
      when 370..379
        self.line_weight = value
      when 1000
        self.ext_data = value
      when 1001
        self.ext_app_name = value
      else
        p "Unrecognized entity group code for type #{type}: (#{code}) #{value}"
      end
    end

    def siblings
      parser.references[soft_pointer]
    end

    def children
      parser.references[handle]
    end

    def attributes
      children.select {|s| s.is_a? Attribute }
    end

    def point
      a = [x, y, z].compact
      return Point.zero if a.empty?

      Geometry::Point[*a]
    end

    def distance(other)
      return unless other

      xd = x - other.x
      yd = y - other.y
      zd = z - other.z
      Math.sqrt(xd * xd + yd * yd + zd * zd)
    end

    private

    def point_from_values(*args)
      Geometry::Point[args.flatten.reverse.drop_while {|a| not a }.reverse]
    end
  end

  class Block < Entity
    attr_accessor :xref

    def parse_pair(code, value)
      case code.to_i
      when 1 then self.xref = value
      when 3
        # ignore block name. Set in 2.
      else
        super
      end
    end
  end

  class BlockRecord < Entity
  end

  class Attribute < Entity
    attr_accessor :default
    attr_accessor :tag

    def parse_pair(code, value)
      case code.to_i
      when 1 then self.default = value
      when 2 then self.tag = value
      else
        super
      end
    end
  end

  class Insert < Entity
    attr_accessor :block_name
    attr_accessor :attributes_present

    def parse_pair(code, value)
      case code.to_i
      when 2 then self.block_name = value
      when 66 then self.attributes_present = value == '1'
      else
        super
      end
    end

    def attributes
      parser.entities.compact.select {|e| e.soft_pointer == handle }
    end

    def block
      parser.object_names[block_name]
    end
  end

  class Point < Entity
  end

  class Circle < Entity
    attr_accessor :x, :y, :z
    attr_accessor :radius

    def parse_pair(code, value)
      case code
      when '40' then self.radius = value.to_f
      else
        super # Handle common and unrecognized codes
      end
    end

    # @!attribute [r] center
    # @return [Point] the composed center of the {Circle}
    def center
      point
    end
  end

  class Line < Entity
    attr_reader :first, :last
    attr_accessor :x1, :y1, :z1
    attr_accessor :x2, :y2, :z2

    def parse_pair(code, value)
      case code
      when '10' then self.x1 = value.to_f
      when '20' then self.y1 = value.to_f
      when '30' then self.z1 = value.to_f
      when '11' then self.x2 = value.to_f
      when '21' then self.y2 = value.to_f
      when '31' then self.z2 = value.to_f
      else
        super # Handle common and unrecognized codes
      end
    end

    def initialize(*args)
      @first, @last = *args
    end

    # @!attribute [r] first
    # @return [Point] the starting point of the {Line}
    def first
      @first ||= point_from_values(x1, y1, z1)
    end

    # @!attribute [r] last
    # @return [Point] the end point of the {Line}
    def last
      @last ||= point_from_values(x2, y2, z2)
    end
  end

  class Polyline < Entity
    attr_reader :closed
    attr_accessor :points

    def initialize(closed)
      @closed = closed
      @points = []
    end
  end

  class LWPolyline < Entity
    # @!attribute points
    # @return [Array<Point>] The points that make up the polyline
    attr_reader :points

    def initialize(*points)
      @points = points.map {|a| Geometry::Point[a]}
    end

    # Return the individual line segments
    def lines
      points.each_cons(2).map {|a,b| Line.new a, b}
    end
  end

  class Spline < Entity
    attr_reader :degree
    attr_reader :knots
    attr_reader :points

    def initialize(degree:nil, knots:[], points:nil)
      @degree = degree
      @knots = knots || []
      @points = points || []
    end
  end

  class Bezier < Spline
    # @!attribute degree
    # @return [Number] The degree of the curve
    def degree
      points.length - 1
    end

    # @!attribute points
    # @return [Array<Point>] The control points for the Bézier curve
    attr_reader :points

    def initialize(*points)
      @points = points.map {|v| Geometry::Point[v]}
    end

    # http://en.wikipedia.org/wiki/Binomial_coefficient
    # http://rosettacode.org/wiki/Evaluate_binomial_coefficients#Ruby
    def binomial_coefficient(k)
      (0...k).inject(1) {|m,i| (m * (degree - i)) / (i + 1) }
    end

    # @param t [Float] the input parameter
    def [](t)
      return nil unless (0..1).include?(t)
      result = Geometry::Point.zero(points.first.size)
      points.each_with_index do |v, i|
        result += v * binomial_coefficient(i) * ((1 - t) ** (degree - i)) * (t ** i)
      end
      result
    end

    # Convert the {Bezier} into the given number of line segments
    def lines(count=20)
      (0..1).step(1.0/count).map {|t| self[t]}.each_cons(2).map {|a,b| Line.new a, b}
    end
  end

  class Text < Entity
    attr_accessor :value
    attr_accessor :height
    attr_accessor :ratio
    attr_accessor :rotation
    attr_accessor :x, :y, :z

    def parse_pair(code, value)
      case code
      when '1' then self.value = value
      when '10' then self.x = value.to_f
      when '20' then self.y = value.to_f
      when '30' then self.z = value.to_f
      when '40' then self.height = value.to_f
      when '41' then self.ratio = value.to_f
      when '50' then self.rotation = value.to_f
      else
        super # Handle common and unrecognized codes
      end
    end

    def position
      a = [x, y, z]
      a.pop until a.last
      Geometry::Point[*a]
    end
  end

  class MText < Text
    attr_accessor :style
    attr_accessor :cleaned

    def value=(value)
      self.cleaned = value.dup
      self.cleaned.gsub!(/\\(\w).*?(.*?)(;|$)/, "") # remove commands
      self.cleaned.gsub!(/[{}]/, "") # remove groups
      super(value)
    end

    def parse_pair(code, value)
      case code
      when '7' then self.style = value
      else
        super
      end
    end
  end
end

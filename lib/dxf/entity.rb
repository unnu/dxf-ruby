require 'geometry'
require 'pry'

require_relative 'cluster_factory'
require_relative 'data'
require_relative 'field'
require_relative 'has_entries'
require_relative 'has_point'

module DXF
  class Object
    TypeError = Class.new(StandardError)

    def self.inherited(subclass)
      @fields = subclass.fields.dup
      super
    end

    def self.marker(name)
      @marker = name
      yield
      @marker = nil
    end

    def self.field(code, name, &block)
      attr_accessor name
      fields[code] = block || Field.new(@marker, code, name, nil, block)
    end

    class << self
      def fields
        @fields ||= {}
      end
    end

    def fields
      self.class.fields
    end

    attr_accessor :type
    attr_accessor :parser
    attr_accessor :data

    attr_accessor :color
    attr_accessor :name
    attr_accessor :handle
    attr_accessor :space
    attr_accessor :rotation_angle
    attr_accessor :scale_x, :scale_y, :scale_z
    attr_accessor :line_type
    attr_accessor :line_weight
    attr_accessor :soft_pointer
    attr_accessor :hard_pointer
    attr_accessor :soft_pointer_owner
    attr_accessor :hard_pointer_owner
    attr_accessor :subclass_marker
    attr_accessor :ext_data
    attr_accessor :ext_app_name
    attr_accessor :acad
    attr_accessor :transparency

    def self.create(type, parser)
      object = case type
      when 'CIRCLE' then Circle.new
      when 'LINE' then Line.new
      when 'POINT' then Point.new
      when 'SPLINE' then Spline.new
      when 'TEXT' then Text.new
      when 'MTEXT' then MText.new
      when 'ATTRIB' then Attribute.new
      when 'SEQEND' then EndSequence.new
      when 'INSERT' then Insert.new
      when 'BLOCK' then Block.new
      when 'ENDBLK' then EndBlock.new
      when 'BLOCK_RECORD' then BlockRecord.new
      when 'APPID' then AppId.new
      when 'TABLE' then Table.new
      when 'ENDTAB' then EndTable.new
      when 'CLASS' then Klass.new
      else
        self.new
        # raise TypeError, "Unrecognized object type '#{type}'"
      end

      object.type = type
      object.parser = parser
      object.data = Data.new
      object.acad = []
      object
    end

    def parse_pair(code, value)
      if field = self.class.fields[code.to_i]
        field.deserialize(self, value)
        return
      end

      case code.to_i
      when 2
        self.name = value
      when 5
        self.handle = value
      when 6
        self.line_type = value
      when 41
        self.scale_x = value
      when 42
        self.scale_y = value
      when 43
        self.scale_z = value
      when 50
        self.rotation_angle = value
      when 62
        self.color = value.to_i
      when 67
        self.space = value == '1' ? :paper : :model
      when 100
        self.subclass_marker = value
      when 102
        self.acad << value
      when 330..339
        self.soft_pointer = value
      when 340..349
        self.hard_pointer = value
      when 350..359
        self.soft_pointer_owner = value
      when 360..369
        self.hard_pointer_owner = value
      when 370..379
        self.line_weight = value
      when 440
        self.transparency = value
      when 1000
        self.ext_data = value
      when 1001
        self.ext_app_name = value
      else
        p "Unrecognized object group code for type #{type}: (#{code}) #{value}"
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

    def serialize
      fields.values.each do |field|
        field.serialize(self, data)
      end
      data.serialize
    end

    private

    def point_from_values(*args)
      Geometry::Point[args.flatten.reverse.drop_while {|a| not a }.reverse]
    end
  end

  class Entity < Object
    marker 'AcDbEntity' do
      field 8, :layer
    end
  end

  class Klass < Object
    field 1, :record_name
  end

  class Block < Entity
    include HasEntries

    marker 'AcDbBlockBegin' do
      include HasPoint
      field 2, :name
      field 1, :xref
    end
  end

  class EndBlock < Entity
    include HasEntries
  end

  class BlockRecord < Object
    INSERT_UNITS = %i(inch feet mile millimeter centimeter meter kilometer
                      microinch mil yard angstrom nanometer micron decimeter
                      decameter hectometer gigameter astronomical-unit
                      light-year parsec)

    attr_accessor :explodability
    attr_accessor :scalability
    attr_accessor :insert_units

    def parse_pair(code, value)
      case code.to_i
      when 70 then self.insert_units = INSERT_UNITS[value - 1]
      when 280 then self.explodability = value
      when 281 then self.scalability = value
      else
        super
      end
    end
  end

  class Attribute < Object
    include HasPoint

    marker 'AcDbText' do
      field 1,   :default
    end
  end

  class EndSequence < Object
  end

  class Insert < Object
    marker 'AcDbBlockReference' do
      field 66, :attributes_follow
      field 2, :block_name
      include HasPoint
    end

    def attributes
      parser.entities.compact.select {|e| e.soft_pointer == handle }
    end

    def block
      parser.object_names[block_name]
    end
  end

  class Point < Object
    include HasPoint
  end

  class Table < Object
    include HasEntries
  end

  class EndTable < Object
    include HasEntries
  end

  class Circle < Object
    include HasPoint

    marker 'AcDbCircle' do
      field 40, :radius
    end

    def center
      point
    end
  end

  class Line < Object
    include HasPoint

    attr_reader :first, :last
    attr_accessor :x2, :y2, :z2

    def parse_pair(code, value)
      case code
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
      @first ||= point
    end

    # @!attribute [r] last
    # @return [Point] the end point of the {Line}
    def last
      @last ||= point_from_values(x2, y2, z2)
    end
  end

  class Polyline < Object
    include HasPoint

    attr_reader :closed
    attr_accessor :points

    def initialize(closed)
      @closed = closed
      @points = []
    end
  end

  class LWPolyline < Object
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

  class Spline < Object
    include HasPoint

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

  class Text < Object
    include HasPoint

    marker 'AcDbText' do
      field 1,   :default
      field 40,  :height
    end

    attr_accessor :value
    attr_accessor :ratio
    attr_accessor :rotation

    def parse_pair(code, value)
      case code.to_i
      when 1 then self.value = value
      when 41 then self.ratio = value.to_f
      when 50 then self.rotation = value.to_f
      else
        super # Handle common and unrecognized codes
      end
    end
  end

  class MText < Text
    ALIGNMENTS = %i(top_left top_center top_right
                   middle_left middle_center middle_right
                   bottom_left bottom_center bottom_right)
    DIRECTIONS = %i(left_to_right top_to_bottom by_style)
    SPACING_STYLE = %i(at_least exact)

    include HasPoint

    attr_accessor :style
    attr_accessor :alignment
    attr_accessor :height
    attr_accessor :spacing
    attr_accessor :spacing_style
    attr_accessor :scale
    attr_accessor :direction
    attr_accessor :cleaned

    def value=(value)
      self.cleaned = value.dup
      self.cleaned.gsub!(/\\(\w).*?(.*?)(;|$)/, "") # remove commands
      self.cleaned.gsub!(/[{}]/, "") # remove groups
      super(value)
    end

    def parse_pair(code, value)
      case code.to_i
      when 7 then self.style = value
      when 43 then self.height = value
      when 44 then self.spacing = value
      when 46 then self.scale = value
      when 71
        self.alignment = ALIGNMENTS[value - 1]
      when 72
        self.direction = DIRECTIONS[value - 1]
      when 73
        self.spacing_style = SPACING_STYLE[value - 1]
      else
        super
      end
    end
  end

  class AppId < Object
    marker 'AcDbRegAppTableRecord' do
      field 2,  :application_name
      field 70, :flags
    end
  end
end

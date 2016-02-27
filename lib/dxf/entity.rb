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
      subclass.fields = fields.dup
      super
    end

    def self.marker(name)
      @marker = name
      yield
      @marker = nil
    end

    def self.field(code, name, default = nil)
      attr_accessor name
      fields[code] = Field.new(@marker, code, name, default)
    end

    class << self
      def fields
        @fields ||= {}
      end

      def fields=(fields)
        @fields = fields
      end
    end

    def fields
      self.class.fields
    end

    attr_accessor :dxf

    def self.register(type)
      @@types ||= {}
      @@types[type] = self
      @type = type
    end

    def self.type
      @type
    end

    def self.create(type, dxf)
      klass = @@types[type]
      klass ||= self

      object = klass.new
      object.type = type
      object.dxf = dxf
      object
    end

    field 0, :type

    def initialize(fields = {})
      self.type = self.class.type

      self.fields.each do |_, field|
        public_send("#{field.name}=", field.default) if field.default
      end

      fields.each do |field, value|
        public_send("#{field}=", value)
      end
    end

    def parse_pair(code, value)
      if field = self.class.fields[code.to_i]
        field.deserialize(self, value)
        return
      end

      # p "Unrecognized object group code for type #{type}: (#{code}) #{value}"
    end

    def siblings
      dxf.references[soft_pointer]
    end

    def children
      dxf.references[handle]
    end

    def serialize
      fields.values.each do |field|
        field.serialize(self, data)
      end
      data.serialize
    end

    def end_class
      nil
    end

    def data
      @data ||= Data.new
    end

    private

    def point_from_values(*args)
      Geometry::Point[args.flatten.reverse.drop_while {|a| not a }.reverse]
    end
  end

  class Entity < Object
    field 5, :handle
    field 330, :soft_pointer

    marker 'AcDbEntity' do
      field 8, :layer_name
    end
  end

  class Layer < Object
    register 'LAYER'

    marker 'AcDbLayerTableRecord' do
      field 2, :name
    end
  end

  class Klass < Object
    register 'CLASS'

    field 1, :record_name
  end

  class EndBlock < Entity
    register 'ENDBLK'

    include HasEntries
  end

  class Block < Entity
    register 'BLOCK'

    include HasEntries

    marker 'AcDbBlockBegin' do
      include HasPoint
      field 2, :name
      field 1, :xref
    end

    def block_record
      dxf.types[DXF::BlockRecord].find {|block_record| block_record.block_name == name }
    end

    def inserts
      dxf.types[DXF::Insert].select {|insert| insert.block_name == name }
    end

    def add(object)
      case object
      when AttributeDefinition
        object.soft_pointer = block_record.handle
        object.layer_name = layer_name
      else
        raise ArgumentError, "#{object.class} cannot be added to #{self.class}"
      end
      super
    end

    def end_class
      EndBlock
    end
  end

  class BlockRecord < Object
    register 'BLOCK_RECORD'

    INSERT_UNITS = %i(inch feet mile millimeter centimeter meter kilometer
                      microinch mil yard angstrom nanometer micron decimeter
                      decameter hectometer gigameter astronomical-unit
                      light-year parsec)

    field 5,   :handle
    field 330, :soft_pointer

    marker'AcDbBlockTableRecord' do
      field 2, :block_name
      field 70, :insertation_units
      field 340, :hard_pointer
      field 280, :explodability
      field 281, :scalability
    end

    def block
      dxf.types[DXF::Block].find {|block| block.name == block_name }
    end
  end

  class Attribute < Entity
    register 'ATTRIB'

    marker 'AcDbText' do
      include HasPoint
      field 1,  :default
      field 40, :height, 1.0
    end

    marker 'AcDbAttribute' do
      field 2,  :tag
      field 70, :flags, 0
    end
  end

  class AttributeDefinition < Entity
    register 'ATTDEF'

    marker 'AcDbText' do
      include HasPoint
      field 1,   :default
      field 40,  :height, 1.0
    end

    marker 'AcDbAttributeDefinition' do
      field 2, :tag
      field 3, :prompt
    end

    def block_record
      dxf.handles[soft_pointer]
    end

    def new_attribute(fields = {})
      attribute = Attribute.new
      %i(height point layer_name default tag).each do |field|
        attribute.public_send("#{field}=", fields[field] || public_send(field))
      end
      attribute
    end
  end

  class EndSequence < Object
    register 'SEQEND'
  end

  class Insert < Entity
    register 'INSERT'

    include HasEntries

    marker 'AcDbBlockReference' do
      field 66, :attributes_follow
      field 2,  :block_name
      include HasPoint
    end

    def attributes
      dxf.references[handle]
    end

    def block
      dxf.types[DXF::Block].find {|block| block.name == block_name }
    end

    def add(object)
      case object
      when Attribute
        object.soft_pointer = handle
      else
        raise ArgumentError, "#{object.class} cannot be added to #{self.class}"
      end
      super
    end

    def end_class
      EndSequence
    end
  end

  class Table < Object
    register 'TABLE'

    include HasEntries

    def end_class
      EndTable
    end
  end

  class EndTable < Object
    register 'ENDTAB'

    include HasEntries
  end

  class Circle < Entity
    register 'CIRCLE'

    include HasPoint

    marker 'AcDbCircle' do
      field 40, :radius
    end

    def center
      point
    end
  end

  class Line < Entity
    register 'LINE'

    marker 'AcDbLine' do
      field 39, :thickness
      include HasPoint
    end
  end

  class Polyline < Entity
    register 'POLYLINE'

    include HasPoint

    attr_reader :closed
    attr_accessor :points

    def initialize(closed)
      @closed = closed
      @points = []
    end
  end

  class LWPolyline < Entity
    register 'LWPOLYLINE'

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
    register 'SPLINE'

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
    register 'BEZIER'

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
    register 'TEXT'

    marker 'AcDbText' do
      include HasPoint
      field 1,   :default
      field 40,  :height
    end
  end

  class MText < Entity
    register 'MTEXT'

    ALIGNMENTS = %i(top_left top_center top_right
                   middle_left middle_center middle_right
                   bottom_left bottom_center bottom_right)
    DIRECTIONS = %i(left_to_right top_to_bottom by_style)
    SPACING_STYLE = %i(at_least exact)

    marker 'AcDbMText' do
      include HasPoint
      field 1,  :text
      field 41, :reference_rectangle_width
    end

    def cleaned
      text
        .gsub(/\\(\w).*?(.*?)(;|$)/, "") # remove commands
        .gsub!(/[{}]/, "") # remove groups
    end
  end

  class AppId < Object
    register 'APPID'

    marker 'AcDbRegAppTableRecord' do
      field 2,  :application_name
      field 70, :flags
    end
  end
end

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

    def self.field(code, name, &block)
      attr_accessor name
      fields[code] = Field.new(@marker, code, name, nil, block)
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

    attr_accessor :type
    attr_accessor :parser
    attr_accessor :data
    attr_accessor :acad

    def self.create(type, parser)
      object = case type
      when 'CIRCLE' then Circle.new
      when 'LINE' then Line.new
      when 'SPLINE' then Spline.new
      when 'TEXT' then Text.new
      when 'MTEXT' then MText.new
      when 'ATTRIB' then Attribute.new
      when 'ATTDEF' then AttributeDefinition.new
      when 'SEQEND' then EndSequence.new
      when 'INSERT' then Insert.new
      when 'BLOCK' then Block.new
      when 'ENDBLK' then EndBlock.new
      when 'BLOCK_RECORD' then BlockRecord.new
      when 'APPID' then AppId.new
      when 'TABLE' then Table.new
      when 'ENDTAB' then EndTable.new
      when 'CLASS' then Klass.new
      when 'LAYER' then Layer.new
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

      # p "Unrecognized object group code for type #{type}: (#{code}) #{value}"
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
    field 5, :handle
    field 330, :soft_pointer

    marker 'AcDbEntity' do
      field 8, :layer_name
    end
  end

  class Layer < Object
    marker 'AcDbLayerTableRecord' do
      field 2, :name
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

    field 5, :handle

    marker'AcDbBlockTableRecord' do
      field 2, :name
      field 70, :insertation_units
      field 340, :hard_pointer
      field 280, :explodability
      field 281, :scalability
    end
  end

  class Attribute < Entity
    include HasPoint

    marker 'AcDbText' do
      field 1,   :default
    end
  end

  class AttributeDefinition < Entity
    marker 'AcDbText' do
      include HasPoint
      field 1,   :default
      field 40,  :height
    end

    marker 'AcDbAttributeDefinition' do
      field 2, :tag
      field 3, :prompt
    end
  end

  class EndSequence < Object
  end

  class Insert < Entity
    marker 'AcDbBlockReference' do
      field 66, :attributes_follow
      field 2,  :block_name
      include HasPoint
    end

    def attributes
      parser.references[handle]
    end

    def block
      parser.object_names[block_name]
    end
  end

  class Table < Object
    include HasEntries
  end

  class EndTable < Object
    include HasEntries
  end

  class Circle < Entity
    include HasPoint

    marker 'AcDbCircle' do
      field 40, :radius
    end

    def center
      point
    end
  end

  class Line < Entity
    marker 'AcDbLine' do
      field 39, :thickness
      include HasPoint
    end
  end

  class Polyline < Entity
    include HasPoint

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

  class Text < Entity
    marker 'AcDbText' do
      include HasPoint
      field 1,   :default
      field 40,  :height
    end
  end

  class MText < Entity
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
    marker 'AcDbRegAppTableRecord' do
      field 2,  :application_name
      field 70, :flags
    end
  end
end

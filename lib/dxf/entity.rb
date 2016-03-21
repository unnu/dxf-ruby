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

    class << self
      def inherited(subclass)
        subclass.fields = fields.dup
        super
      end

      def marker(name)
        @marker = name
        yield
        @marker = nil
      end

      def array(code, name = nil)
        @array_code = code
        @array_name = name
        yield
        @array_code = nil
        @array_name = nil
      end

      def field_key(marker, code)
        marker ? "#{marker}_#{code}" : code.to_s
      end

      def field(code, name, default: nil, serialize: nil, deserialize: nil)
        fields[field_key(@marker, code)] = Field.new(
          @marker,
          code,
          name,
          default: default,
          serializer: serialize,
          deserializer: deserialize,
          array_code: @array_code,
          array_name: @array_name
        )

        if @array_code
          attr_writer name
          class_eval <<-end_eval, __FILE__, __LINE__
            def #{name}
              @#{name} ||= []
            end
          end_eval
        else
          attr_accessor name
        end
      end

      def fields
        @fields ||= {}
      end

      def fields=(fields)
        @fields = fields
      end

      def register(type)
        @@types ||= {}
        @@types[type] = self
        @type = type
      end

      def type
        @type
      end

      def create(type, dxf)
        klass = @@types[type]
        klass ||= self

        object = klass.new
        object.type = type
        object.dxf = dxf
        object
      end
    end

    def fields
      self.class.fields
    end

    attr_accessor :dxf

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
      code = code.to_i
      @current_marker = value if code == 100

      if field = self.class.fields[self.class.field_key(@current_marker, code)]
        field.deserialize(self, value)
      else
        # p "Unrecognized object group code for type #{type}: (#{code}) #{value}"
      end
    end

    def siblings
      dxf.references[soft_pointer]
    end

    def children
      dxf.references[handle]
    end

    def serialize
      fields.each do |_, field|
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
    COLOR_BYLAYER = 256

    field 5, :handle
    field 330, :soft_pointer

    marker 'AcDbEntity' do
      field 8,  :layer_name
      field 62, :color
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
      when Text
      when MText
      else
        raise ArgumentError, "#{object.class} cannot be added to #{self.class}"
      end
      object.soft_pointer = block_record.handle
      object.layer_name = layer_name
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
      array 102, 'BLKREFS' do
        field 331, :insert_soft_pointers
      end
    end

    def block
      dxf.types[DXF::Block].find {|block| block.name == block_name }
    end
  end

  class Attribute < Entity
    register 'ATTRIB'

    JUSTIFICATION_X = %i(left center right aligned middle fit)
    JUSTIFICATION_Y = %i(baseline bottom middle top)

    marker 'AcDbText' do
      include HasPoint
      include HasPoint2
      field 1,  :default
      field 7,  :style
      field 40, :height, default: 1.0
      field 41, :width
      field 50, :rotation
      field 72, :justify_x,
        serialize:   ->(object) { JUSTIFICATION_X.index(object.justify_x) },
        deserialize: ->(object, value) { JUSTIFICATION_X[value] }
    end

    marker 'AcDbAttribute' do
      field 2,   :tag
      field 70,  :flags, default: 0
      field 74, :justify_y,
        serialize:   ->(object) { JUSTIFICATION_Y.index(object.justify_x) },
        deserialize: ->(object, value) { JUSTIFICATION_Y[value] }
    end

    def insert
      dxf.handles[soft_pointer]
    end

    def remove
      insert.remove_attribute(self)
      self.soft_pointer = nil
      self
    end

    def definition
      insert.block.entries.select {|e| e.is_a?(DXF::AttributeDefinition) }.find {|e| e.tag == tag }
    end
  end

  class AttributeDefinition < Entity
    register 'ATTDEF'

    JUSTIFICATION_X = %i(left center right aligned middle fit)
    JUSTIFICATION_Y = %i(baseline bottom middle top)

    marker 'AcDbText' do
      include HasPoint
      field 1,  :default, default: '-'
      field 7,  :style
      field 40, :height, default: 1.0
      field 41, :width
      field 50, :rotation
      field 72, :justify_x,
        serialize:   ->(object) { JUSTIFICATION_X.index(object.justify_x) },
        deserialize: ->(object, value) { JUSTIFICATION_X[value] }
    end

    marker 'AcDbAttributeDefinition' do
      field 280, :version, default: 0
      field 2,   :tag
      field 70,  :flags, default: 0
      field 3,   :prompt
      field 74,  :justify_y,
        serialize:   ->(object) { JUSTIFICATION_Y.index(object.justify_x) },
        deserialize: ->(object, value) { JUSTIFICATION_Y[value] }
    end

    def block_record
      dxf.handles[soft_pointer]
    end

    def block
      block_record.block
    end

    def new_attribute(fields = {})
      attribute = Attribute.new

      %i(justify_x justify_y rotation width style height point layer_name default tag).each do |name|
        attribute.public_send("#{name}=", public_send(name))
      end

      fields.each do |name, value|
        attribute.public_send("#{name}=", value)
      end

      attribute
    end

    def remove
      block.entries.delete(self)
      self.soft_pointer = nil
      self
    end
  end

  class EndSequence < Entity
    register 'SEQEND'
  end

  class Insert < Entity
    register 'INSERT'

    include HasEntries

    marker 'AcDbBlockReference' do
      field 66, :attributes_follow, default: false
      field 2,  :block_name
      include HasPoint
    end

    def block
      dxf.types[DXF::Block].find {|block| block.name == block_name }
    end

    def add(object)
      raise ArgumentError, "#{object.class} cannot be added to #{self.class}" unless object.is_a?(Attribute)

      object.soft_pointer = handle
      object.layer_name = layer_name
      self.attributes_follow = true

      super
    end

    def remove_attribute(attribute)
      entries.delete(attribute)
      self.attributes_follow = entries.any?
    end

    def destroy
      block.block_record.insert_soft_pointers.delete(handle)
      dxf.entities.delete(self)
    end

    def end_class
      EndSequence if attributes_follow
    end

    def end_object
      if attributes_follow
        @end_object ||= EndSequence.new.tap do |end_sequence|
          end_sequence.handle = dxf.create_handle
          end_sequence.soft_pointer = handle
          end_sequence.layer_name = layer_name
        end
      end
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

    marker 'AcDbCircle' do
      include HasPoint
      field 40, :radius
    end

    def center
      point
    end
  end

  class Line < Entity
    register 'LINE'

    marker 'AcDbLine' do
      include HasPoint
      include HasPoint2
      field 39, :thickness
    end

    def length
      distance(point2)
    end
  end

  class Polyline < Entity
    register 'POLYLINE'

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

    JUSTIFICATION_X = %i(left center right aligned middle fit)

    marker 'AcDbText' do
      include HasPoint
      include HasPoint2
      field 1,  :default
      field 7,  :style
      field 40, :height, default: 1.0
      field 41, :width
      field 72, :justify_x,
        serialize:   ->(object) { JUSTIFICATION_X.index(object.justify_x) },
        deserialize: ->(object, value) { JUSTIFICATION_X[value] }
    end

    def serialize
      data = super
      data << [100, "AcDbText"]
      data
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
      field 7,  :style
      field 40, :height, default: 1.0
      field 41, :width
      field 71, :align,
        serialize:   ->(object) { ALIGNMENTS.index(object.align) + 1 },
        deserialize: ->(object, value) { ALIGNMENTS[value - 1] }
    end

    def block_record
      dxf.handles[soft_pointer]
    end

    def block
      block_record.block
    end

    def cleaned
      text
        .gsub(/\\(\w).*?(.*?)(;|$)/, "") # remove commands
        .gsub!(/[{}]/, "") # remove groups
    end

    def remove
      block.entries.delete(self)
      self.soft_pointer = nil
      self
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

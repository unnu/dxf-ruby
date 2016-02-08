require_relative 'entity'

module DXF
  class Parser
    ParseError = Class.new(StandardError)

    attr_accessor :header
    attr_accessor :tables
    attr_accessor :blocks
    attr_accessor :entities

    attr_accessor :objects
    attr_accessor :object_names
    attr_accessor :references

    def initialize(units=:mm)
      @header = {}
      @blocks = []
      @entities = []
      @tables = []

      @objects = Hash.new
      @object_names = Hash.new
      @references = Hash.new {|h, k| h[k] = [] }
    end

    def parse(io)
      parse_pairs io do |code, value|
        next if '999' == code
        raise ParseError, "DXF files must begin with group code 0, not #{code}" unless '0' == code
        raise ParseError, "Expecting a SECTION, not #{value}" unless 'SECTION' == value
        parse_section(io)
      end
      build_index
      self
    end

    def inspect
      "Parser"
    end

    def build_index
      %w(blocks entities tables).each do |section|
        public_send(section).each do |object|
          @objects[object.handle] = object if object.handle
          @object_names[object.name] = object if object.name
          @references[object.soft_pointer] << object if object.soft_pointer
        end
      end
    end

    private

    def read_pair(io)
      code = io.gets.strip
      value = io.gets.strip.encode('UTF-8')
      value = case code.to_i
              when 1..9
                value.to_s
              when 10..18, 20..28, 30..37, 40..49
                value.to_f
              when 50..58
                value.to_f # degrees
              when 70..78, 90..99, 270..289
                value.to_i
              else
                value
              end

      [code, value]
    end

    def parse_pairs(io, &block)
      while not io.eof?
        code, value = read_pair(io)
        case [code, value]
        when ['0', 'ENDSEC']
          yield code, value # Allow the handler a chance to clean up
          return
        when ['0', 'EOF']
          return
        else
          yield code, value
        end
      end
    end

    def parse_section(io)
      code, value = read_pair(io)
      raise ParseError, 'SECTION must be followed by a section type' unless '2' == code

      case value
      when 'BLOCKS'
        parse_objects(io, blocks,'ENDBLK')
      when 'CLASSES'
        parse_pairs(io) do |code, value|
         # p "#{code} #{value}"
        end
      when 'ENTITIES'
        parse_objects(io, entities, 'SEQEND')
      when 'HEADER'
        parse_header(io)
      when 'OBJECTS'  then parse_pairs(io) {|code, value|} # Ignore until implemented
      when 'TABLES'
        parse_objects(io, tables, 'ENDTAB')
      when 'ACDSDATA' then parse_pairs(io) {|code, value|} # Ignore until implemented
      else
        raise ParseError, "Unrecognized section type '#{value}'"
      end
    end

    def parse_objects(io, collection, end_identifier)
      parse_pairs io do |code, value|
        if 0 == code.to_i
          next if 'ENDSEC' == value
          next if end_identifier == value

          collection.push Entity.new(value, self)
        else
          collection.last.parse_pair(code, value)
        end
      end
    end

    # Parse the HEADER section
    def parse_header(io)
      variable_name = nil
      parse_pairs io do |code, value|
        case code
        when '0' then next
        when '9'
          variable_name = value
        else
          header[variable_name] = value
        end
      end
    end

    # @group Helpers
    def self.code_to_symbol(code)
      case code
      when 10..13 then :x
      when 20..23 then :y
      when 30..33 then :z
      end
    end

    def self.update_point(point, x:nil, y:nil, z:nil)
      a = point ? point.to_a : []
      a[0] = x if x
      a[1] = y if y
      a[2] = z if z
      Geometry::Point[a]
    end
    # @endgroup
  end
end

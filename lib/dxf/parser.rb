require_relative 'entity'
require_relative 'variable'

module DXF
  class Parser
    ParseError = Class.new(StandardError)

    attr_accessor :header
    attr_accessor :klasses
    attr_accessor :tables
    attr_accessor :blocks
    attr_accessor :entities
    attr_accessor :objects
    attr_accessor :acdsdata

    attr_accessor :handles
    attr_accessor :references
    attr_accessor :types

    def initialize(units=:mm)
      @header = {}
      @klasses = []
      @tables = []
      @blocks = []
      @entities = []
      @objects = []
      @acdsdata = []

      @handles = Hash.new
      @references = Hash.new {|h, k| h[k] = [] }
      @types = Hash.new {|h, k| h[k] = [] }
    end

    def parse(io)
      parse_pairs io do |code, value|
        next if '999' == code
        raise ParseError, "DXF files must begin with group code 0, not #{code}" unless '0' == code
        raise ParseError, "Expecting a SECTION, not #{value}" unless 'SECTION' == value
        parse_section(io)
      end
      self
    end

    def create_handle
      handle_int = header['$HANDSEED'].value.to_i(16)
      header['$HANDSEED'].value = (handle_int + 1).to_s(16)
    end

    def inspect
      "Parser"
    end

    private

    def indicate(object)
      @handles[object.handle]    = object if object.respond_to?(:handle) && object.handle
      @references[object.soft_pointer] << object if object.respond_to?(:soft_pointer) && object.soft_pointer
      @types[object.class] << object
    end

    def read_pair(io)
      code = io.gets.strip
      value = io.gets.strip.encode('UTF-8')
      value = case code.to_i
              when 0..9
                value.to_s
              when 10..18, 20..28, 30..37, 40..49
                value.to_f
              when 50..58
                value.to_f # degrees
              when 66
                value == '1'
              when 70..78, 90..99, 270..289
                value.to_i
              when 100
                value.strip
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
        parse_objects(io, blocks)
      when 'CLASSES'  then
        parse_objects(io, klasses)
      when 'ENTITIES'
        parse_objects(io, entities)
      when 'HEADER'
        parse_header(io)
      when 'OBJECTS'
        parse_objects(io, objects)
      when 'TABLES'
        parse_objects(io, tables)
      when 'ACDSDATA'
        parse_objects(io, acdsdata)
      else
        raise ParseError, "Unrecognized section type '#{value}'"
      end
    end

    def parse_objects(io, collection)
      parent = nil
      entity = nil

      parse_pairs io do |code, value|
        if 0 == code.to_i
          if parent
            # parent = nil unless parent.end_class

            if entity.is_a?(parent.end_class)
              parent.end_object = entity
              parent = nil
            else
              parent.entries << entity
            end
          elsif entity
            parent = entity if entity.end_class
            collection << entity
          end

          indicate(entity) if entity

          if 'ENDSEC' == value
            parent = nil
            next
          end

          entity = Object.create(value, self)
        end

        entity.data.push(code, value)
        entity.parse_pair(code, value)
      end
    end

    # Parse the HEADER section
    def parse_header(io)
      variable_name = nil
      parse_pairs io do |code, value|
        case code
        when '0' then next
        when '9'
          header[value] = Variable.new(value)
        else
          header.values.last.parse_pair(code, value)
        end
      end
    end

    def self.code_to_symbol(code)
      case code
      when 10..13 then :x
      when 20..23 then :y
      when 30..33 then :z
      end
    end

  end
end

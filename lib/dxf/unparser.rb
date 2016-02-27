require_relative 'entity'

module DXF
  class Unparser
    def unparse(io, dxf)
      @io = io

      section 'HEADER' do
        dxf.header.each do |_, variable|
          write(variable.serialize)
        end
      end

      section 'CLASSES' do
        dxf.klasses.each do |klass|
          write(klass.serialize)
        end
      end

      section 'TABLES' do
        dxf.tables.each do |table|
          write(table.serialize)
          table.entries.each do |entry|
            write(entry.serialize)
          end
          write(table.end_object.serialize) if table.end_object
        end
      end

      section 'BLOCKS' do
        dxf.blocks.each do |block|
          write(block.serialize)
          block.entries.each do |entry|
            write(entry.serialize)
          end
          write(block.end_object.serialize) if block.end_object
        end
      end

      section 'ENTITIES' do
        dxf.entities.each do |entity|
          write(entity.serialize)
          next unless entity.respond_to? :entries

          entity.entries.each do |entry|
            write(entry.serialize)
          end
          write(entity.end_object.serialize) if entity.end_object
        end
      end

      section 'OBJECTS' do
        dxf.objects.each do |object|
          write(object.serialize)
        end
      end

      if dxf.acdsdata.any?
        section 'ACDSDATA' do
          dxf.acdsdata.each do |data|
            write(data.serialize)
          end
        end
      end

      write_pair(0, 'EOF')
    end

    def section(name)
      write_pair(0, 'SECTION')
      write_pair(2, name)
      yield
      write_pair(0, 'ENDSEC')
    end

    def write(array)
      array.each do |(code, value)|
        write_pair(code, value)
      end
    end

    def write_pair(code, value)
      @io.puts(code)
      encoded_value = case value
                      when Float
                        "%.16f" % value
                      when TrueClass
                        '1'
                      when FalseClass
                        '0'
                      else
                        value
                      end
      @io.puts(encoded_value)
    end
  end
end

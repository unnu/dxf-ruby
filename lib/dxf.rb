require_relative 'dxf/parser'
require_relative 'dxf/unparser'

module DXF
=begin
Reading and writing of files using AutoCAD's {http://en.wikipedia.org/wiki/AutoCAD_DXF Drawing Interchange File} format.

    {http://usa.autodesk.com/adsk/servlet/item?siteID=123112&id=12272454&linkID=10809853 DXF Specifications}
=end

  # Read a DXF file
  # @param [String] filename The path to the file to read
  # @return [DXF] the resulting {DXF} object
  def self.read(filename)
    File.open(filename, 'r:iso-8859-1') {|f| DXF::Parser.new.parse(f) }
    # File.open(filename, 'r') {|f| DXF::Parser.new.parse(f) }
  end

  def self.write(filename, dxf)
    File.open(filename, 'w:iso-8859-1') {|f| DXF::Unparser.new.unparse(f, dxf) }
  end
end

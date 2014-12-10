require 'minitest/autorun'
require 'dxf/parser'

describe DXF::Parser do
  it 'must read from an IO stream' do
    File.open('test/fixtures/circle.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
  end

  it 'must parse a file with a circle' do
    parser = File.open('test/fixtures/circle.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
    parser.entities.length.must_equal 1
    circle = parser.entities.last
    circle.must_be_instance_of(DXF::Circle)
    circle.center.must_equal Geometry::Point[0,0]
    circle.radius.must_equal 1
  end

  it 'must parse a file with a translated circle' do
    parser = File.open('test/fixtures/circle_translate.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
    parser.entities.length.must_equal 1
    circle = parser.entities.last
    circle.must_be_instance_of(DXF::Circle)
    circle.center.must_equal Geometry::Point[1,1]
    circle.radius.must_equal 1
  end

  it 'must parse a file with a lightweight polyline' do
    parser = File.open('test/fixtures/square_lwpolyline_inches.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
    parser.entities.length.must_equal 1
    parser.entities.all? {|a| a.kind_of? DXF::LWPolyline }.must_equal true
    parser.entities.first.points.length.must_equal 4
  end

  it 'must parse a file with a square' do
    parser = File.open('test/fixtures/square_inches.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
    parser.entities.length.must_equal 4
    line = parser.entities.last
    line.must_be_instance_of(DXF::Line)
    line.first.must_equal Geometry::Point[0, 1]
    line.last.must_equal Geometry::Point[0, 0]
  end

  it 'must parse a file with a spline' do
    parser = File.open('test/fixtures/spline.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
    parser.entities.length.must_equal 82
    parser.entities.all? {|a| a.kind_of? DXF::Spline }.must_equal true
  end

  it 'must parse a file with a text' do
    parser = File.open('test/fixtures/text.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
    parser.entities.length.must_equal 1
    text = parser.entities.last
    text.must_be_instance_of(DXF::Text)
    text.position.must_equal Geometry::Point[2,3,4]
    text.height.must_equal 10
    text.value.must_equal "Some Text"
    text.ratio.must_equal 1.0
    text.rotation.must_equal 35.0
  end

  it 'must parse a file with a polyline' do
    parser = File.open('test/fixtures/polyline.dxf', 'r') {|f| DXF::Parser.new.parse(f) }
    parser.entities.length.must_equal 1
    polyline = parser.entities.last
    polyline.must_be_instance_of(DXF::Polyline)
    polyline.points.length.must_equal 3
    polyline.points[0].must_equal Geometry::Point[1,2,3]
    polyline.points[1].must_equal Geometry::Point[10,20,30]
    polyline.points[2].must_equal Geometry::Point[-1,-2,-3]
  end
end

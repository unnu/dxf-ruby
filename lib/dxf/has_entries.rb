module DXF
  module HasEntries
    attr_accessor :end_object

    def entries
      @entries ||= []
    end

    def add(object)
      object.handle ||= dxf.create_handle
      object.dxf = dxf
      entries << object
      object
    end
  end
end

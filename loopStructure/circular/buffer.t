BufferFunctions = {}
BufferMT = {__index = BufferFunctions}

pageSize = 4*1024*terralib.sizeof(&uint8)

function newBuffer(imageSize, stencilWidth)
  local tab = {imageSize=imageSize, 
               data = symbol(&float)}
  setmetatable(tab,BufferMT)
  return tab
end

function BufferFunctions:alloc()
  return quote
    var [self.data]
    cstdlib.posix_memalign( [&&opaque](&[self.data]), pageSize, [self.lineWidth*self.stencilHeight]*sizeof(float))
  end
end

function BufferFunctions:set(pos,value)

end
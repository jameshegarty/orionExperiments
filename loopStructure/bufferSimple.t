local cstdlib = terralib.includec("stdlib.h")

BufferFunctions = {}
BufferMT = {__index = BufferFunctions}

pageSize = 4*1024*terralib.sizeof(&uint8)

function newBuffer(lineWidth, stencilHeight)
  assert(type(lineWidth)=="number")
  assert(type(stencilHeight)=="number")

  local tab = {lineWidth=lineWidth, 
               stencilHeight=stencilHeight, 
               data=symbol(&float),
               xposGet = symbol(int),
               yposGet = symbol(int),
               xposSet = symbol(int),
               yposSet = symbol(int)}
  setmetatable(tab,BufferMT)
  return tab
end

function BufferFunctions:alloc()
  return quote
    var [self.data]
    cstdlib.posix_memalign( [&&opaque](&[self.data]), pageSize, [self.lineWidth*self.stencilHeight]*sizeof(float))
    var [self.xposGet]
    var [self.yposGet]
    var [self.xposSet]
    var [self.yposSet]
  end
end



function BufferFunctions:get(relX, relY)
  if (type(relX)=="number" or terralib.issymbol(relX)) and 
      (type(relY)=="number" or terralib.issymbol(relY)) then
--    return `[self.data][ (([self.yposGet]+relY)*[self.lineWidth]+[self.xposGet]+relX) % [self.lineWidth*self.stencilHeight]]
    return `terralib.attrload([&vector(float,V)](self.data + (([self.yposGet]+relY)*[self.lineWidth]+[self.xposGet]+relX) % [self.lineWidth*self.stencilHeight]),{align=V})
  end
  assert(false)
end

function BufferFunctions:set(value)
  return quote
--    [self.data][ ([self.yposSet]*[self.lineWidth]+[self.xposSet]) % [self.lineWidth*self.stencilHeight]] = value
    @[&vector(float,V)](self.data+ (([self.yposSet]*[self.lineWidth]+[self.xposSet]) % [self.lineWidth*self.stencilHeight])) = value 
end
end

function BufferFunctions:setptrPos(x,y)
  return quote
    [self.xposSet] = x;
    [self.yposSet] = y;
end

end


function BufferFunctions:getptrPos(x,y)
  return quote
    [self.xposGet] = x;
    [self.yposGet] = y;
end
end

function BufferFunctions:setptrNext(V)
  return quote [self.xposSet] = [self.xposSet]+V; end
end

function BufferFunctions:setptrNextLine(lineWidth)
  assert(type(lineWidth)=="number")
  return quote [self.xposSet] = [self.xposSet]-lineWidth; 
    [self.yposSet] = [self.yposSet] + 1;
end

end

function BufferFunctions:getptrNext(V)
  return quote [self.xposGet] = [self.xposGet]+V; end
end

function BufferFunctions:getptrNextLine(lineWidth)
  assert(type(lineWidth)=="number")
  return quote [self.xposGet] = [self.xposGet]-lineWidth; 
    [self.yposGet] = [self.yposGet] + 1;
end

end
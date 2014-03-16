-- a fake line buffer, that only works on fully associative
-- kernels.

local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")

BufferFunctions = {}
BufferMT = {__index = BufferFunctions}

pageSize = 4*1024*terralib.sizeof(&uint8)

function newBuffer(lineWidth, stencilHeight, getCorrectly)
  assert(type(lineWidth)=="number")
  assert(type(stencilHeight)=="number")

  local tab = {lineWidth=lineWidth, 
               stencilHeight=stencilHeight, 
               getCorrectly = getCorrectly,
               getCorrectlyOffset = symbol(int),
               data = symbol(&float),
               IVset = symbol(&float),
               IVget = symbol(&float)}

  setmetatable(tab,BufferMT)
  return tab
end

function BufferFunctions:alloc()
  return quote
    var [self.data]
    cstdlib.posix_memalign( [&&opaque](&[self.data]), pageSize, [self.lineWidth*self.stencilHeight]*sizeof(float))
    var [self.IVset]
    var [self.IVget]
    var [self.getCorrectlyOffset]
  end

end

function BufferFunctions:get(relX, relY)
  if (type(relX)=="number" or terralib.issymbol(relX)) and 
      (type(relY)=="number" or terralib.issymbol(relY)) then

    if self.getCorrectly then
      -- a total dirty hack. We know, when we're reading this line, we want to read the line that was just set by the producer
      return quote
        var fptr : &float = self.IVset-[self.lineWidth]+[self.getCorrectlyOffset]
        if fptr < [self.data] then fptr = fptr + [self.lineWidth]*[self.stencilHeight] end
          in
        terralib.attrload([&vector(float,V)](fptr),{align=V})
        end
    else
      return `terralib.attrload([&vector(float,V)](self.IVget+relY*[self.lineWidth]+relX),{align=V})
    end
  end
  assert(false)
end

function BufferFunctions:set(value)
  return quote
    @[&vector(float,V)](self.IVset) = value 
  end
end

function BufferFunctions:setptrPos(x,y)
  assert(type(x)=="number")
  assert(type(y)=="number")

  return quote
    [self.IVset] = [self.data]+x
  end
end

function BufferFunctions:getptrPos(x,y)
  assert(type(x)=="number")
  assert(type(y)=="number")

  if self.getCorrectly then
    return quote [self.getCorrectlyOffset] = 0 end
  else
    return quote
      [self.IVget] = [self.data]+[self.lineWidth]*[self.stencilHeight-1]+x
    end
  end
end

function BufferFunctions:setptrNext(V)
  return quote [self.IVset] = [self.IVset] + V end
end

function BufferFunctions:setptrNextLine(lineWidth)
  return quote 
    [self.IVset] = [self.IVset] - lineWidth + [self.lineWidth];
    while [self.IVset] >= [self.data]+[self.lineWidth*self.stencilHeight] do
      [self.IVset] = [self.IVset] - [self.lineWidth*self.stencilHeight];
--      cstdio.printf("WRAP\n")
    end

  end
end

function BufferFunctions:getptrNext(V)
  if self.getCorrectly then
    return quote [self.getCorrectlyOffset] = [self.getCorrectlyOffset] + V end
  else
    return quote [self.IVget] = [self.IVget] + V end
  end
end

function BufferFunctions:getptrNextLine(lineWidth)
  if self.getCorrectly then
    return quote [self.getCorrectlyOffset] = 0 end
  else
    return quote [self.IVget] = [self.IVget] - lineWidth end
  end
end
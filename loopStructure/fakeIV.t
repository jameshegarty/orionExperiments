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
               IVget = symbol(&float),
               internal={},
               internalVars={}}

  if codegenAsFunctionCall then
    tab.internalVars.IVset = symbol(&&float)
    tab.internalVars.IVget = symbol(&&float)
    tab.internalVars.getCorrectlyOffset = symbol(&int)
    tab.internalVars.data = symbol(&&float)

    tab.internal.IVset = `@[tab.internalVars.IVset]
    tab.internal.IVget = `@[tab.internalVars.IVget]
    tab.internal.getCorrectlyOffset = `@[tab.internalVars.getCorrectlyOffset]
    tab.internal.data = `@[tab.internalVars.data]
  else
    tab.internal.IVset = tab.IVset
    tab.internal.IVget = tab.IVget
    tab.internal.getCorrectlyOffset = tab.getCorrectlyOffset
    tab.internal.data = tab.data
  end

  setmetatable(tab,BufferMT)
  return tab
end

function BufferFunctions:arguments()
  return {`&[self.IVset],`&[self.IVget],`&[self.data],`&[self.getCorrectlyOffset]}
end

function BufferFunctions:formalParameters()
  return {self.internalVars.IVset, self.internalVars.IVget,self.internalVars.data,self.internalVars.getCorrectlyOffset}
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
--  if (type(relX)=="number" or terralib.issymbol(relX)) and 
--      (type(relY)=="number" or terralib.issymbol(relY)) then

    if self.getCorrectly then
      -- a total dirty hack. We know, when we're reading this line, we want to read the line that was just set by the producer
      return quote
        var fptr : &float = [self.internal.IVset]-[self.lineWidth]+[self.internal.getCorrectlyOffset]
        if fptr < [self.internal.data] then fptr = fptr + [self.lineWidth]*[self.stencilHeight] end
          in
        terralib.attrload([&vector(float,V)](fptr),{align=V})
        end
    else
      return `terralib.attrload([&vector(float,V)]([self.internal.IVget]+relY*[self.lineWidth]+relX),{align=V})
    end
--  end
--  assert(false)
end

function BufferFunctions:getSet(relX)
      return `terralib.attrload([&vector(float,V)]([self.internal.IVset]+relX),{align=V})
end
function BufferFunctions:set(value)
  return quote
    @[&vector(float,V)]([self.internal.IVset]) = value 
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
  return quote [self.internal.IVset] = [self.internal.IVset] + V end
end

function BufferFunctions:setptrNextLine(lineWidth)
  return quote 
    [self.internal.IVset] = [self.internal.IVset] - lineWidth + [self.lineWidth];
    while [self.internal.IVset] >= [self.internal.data]+[self.lineWidth*self.stencilHeight] do
      [self.internal.IVset] = [self.internal.IVset] - [self.lineWidth*self.stencilHeight];
--      cstdio.printf("WRAP\n")
    end

  end
end

function BufferFunctions:getptrNext(V)
  if self.getCorrectly then
    return quote [self.internal.getCorrectlyOffset] = [self.internal.getCorrectlyOffset] + V end
  else
    return quote [self.internal.IVget] = [self.internal.IVget] + V end
  end
end

function BufferFunctions:getptrNextLine(lineWidth)
  if self.getCorrectly then
    return quote [self.internal.getCorrectlyOffset] = 0 end
  else
    return quote [self.internal.IVget] = [self.internal.IVget] - lineWidth end
  end
end
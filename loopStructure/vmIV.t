-- a fake line buffer, that only works on fully associative
-- kernels.

local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")

local C = terralib.includecstring [[
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>
#include <assert.h>

  void * ring_buffer_create (unsigned long order) {
  char path[] = "/tmp/ring-buffer-XXXXXX";
  int file_descriptor = mkstemp(path);
  
  assert(file_descriptor > 0);
  assert(!unlink(path));
 
  int bytes = 1UL << order;
  assert(!ftruncate(file_descriptor, bytes));
  
  void * address = mmap (NULL, bytes << 1, PROT_NONE,
                         MAP_ANON | MAP_PRIVATE, -1, 0);
 
  assert(address != MAP_FAILED);
  void * addressp =
    mmap(address, bytes, PROT_READ | PROT_WRITE,
         MAP_FIXED | MAP_SHARED, file_descriptor, 0);
 
    assert(address == addressp);
  
    addressp = mmap ((char*)address + bytes,
                  bytes, PROT_READ | PROT_WRITE,
                  MAP_FIXED | MAP_SHARED, file_descriptor, 0);
    assert(addressp == (char*)address + bytes);
    assert(!close (file_descriptor));
  return address;
                                                  }

                                   ]]

-- a % b
-- stupid C mod doesn't treat negative numbers as you'd hope
local terra fixedModulus(a : int,b : int)
  while a < 0 do a = a+b end
  return a % b
end

BufferFunctions = {}
BufferMT = {__index = BufferFunctions}

pageSize = 4*1024*terralib.sizeof(&uint8)

function newBuffer(lineWidth, stencilHeight)
  assert(type(lineWidth)=="number")
  assert(type(stencilHeight)=="number")

  local tab = {lineWidth=lineWidth, 
               stencilHeight=stencilHeight, 
               data = symbol(&float),
               IVset = symbol(&float),
               IVget = symbol(&float),
               yInLineZero = symbol(int), -- this is the Y coord of the line stored starting at address 0 in the LB. If negative LB is not yet initialized
               internal={},
               internalVars={}}

  if codegenAsFunctionCall then
    tab.internalVars.IVset = symbol(&&float)
    tab.internalVars.IVget = symbol(&&float)
    tab.internalVars.data = symbol(&&float)

    tab.internal.IVset = `@[tab.internalVars.IVset]
    tab.internal.IVget = `@[tab.internalVars.IVget]
    tab.internal.data = `@[tab.internalVars.data]
  else
    tab.internal.IVset = tab.IVset
    tab.internal.IVget = tab.IVget
    tab.internal.data = tab.data
  end

  setmetatable(tab,BufferMT)
  return tab
end

function BufferFunctions:arguments()
  return {`&[self.IVset],`&[self.IVget],`&[self.data]}
end

function BufferFunctions:formalParameters()
  return {self.internalVars.IVset, self.internalVars.IVget,self.internalVars.data}
end

function BufferFunctions:alloc()
  return quote
    var [self.data] = [&float](C.ring_buffer_create(18)) -- 4096*16*4
    var [self.IVset]
    var [self.IVget]
    var [self.yInLineZero] = -1
  end

end

function BufferFunctions:get(relX, relY)
  return `terralib.attrload([&vector(float,V)]([self.internal.IVget]+relY*[self.lineWidth]+relX),{align=V})
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
    [self.yInLineZero] = y;
    [self.IVset] = [self.data]+x;
  end
end

function BufferFunctions:getptrPos(x,y)
  assert(type(x)=="number")
  assert(type(y)=="number")

  return quote
    [self.IVget] = [self.data]+[self.lineWidth]*[self.stencilHeight]+fixedModulus( (y-[self.yInLineZero])*[self.lineWidth]+x,[self.lineWidth*self.stencilHeight])
  end
end

function BufferFunctions:setptrNext(V)
  return quote [self.internal.IVset] = [self.internal.IVset] + V end
end

function BufferFunctions:setptrNextLine(lineWidth)
  return quote 
    [self.internal.IVset] = [self.internal.IVset] - lineWidth + [self.lineWidth];
    if [self.internal.IVset] >= [self.internal.data]+[self.lineWidth*self.stencilHeight] then
      [self.internal.IVset] = [self.internal.IVset] - [self.lineWidth*self.stencilHeight];
--      cstdio.printf("WRAP\n")
    end

  end
end

function BufferFunctions:getptrNext(V)
  return quote [self.internal.IVget] = [self.internal.IVget] + V end
end

function BufferFunctions:getptrNextLine(lineWidth)
  return quote [self.internal.IVget] = [self.internal.IVget] - lineWidth + [self.lineWidth]
    if [self.internal.IVget] >= [self.internal.data]+2*[self.lineWidth*self.stencilHeight] then
      [self.internal.IVget] = [self.internal.IVget] - [self.lineWidth*self.stencilHeight];
    end
end
end
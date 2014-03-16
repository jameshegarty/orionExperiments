-- manually managed induction variables
-- how the current orion compiler works

local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")

BufferFunctions = {}
BufferMT = {__index = BufferFunctions}

pageSize = 4*1024*terralib.sizeof(&uint8)

unrollIVLoops = false

-- a % b
-- stupid C mod doesn't treat negative numbers as you'd hope
terra fixedModulus(a : int,b : int)
  while a < 0 do a = a+b end
  return a % b
end


function newBuffer(lineWidth, stencilHeight)
  assert(type(lineWidth)=="number")
  assert(type(stencilHeight)=="number")

  --- meh we'll just assume stencilHeight and stencil Width are the same 

  local tab = {lineWidth=lineWidth, 
               stencilHeight=stencilHeight, 
               -- data is the linebuffer. data at smaller Y locations are stored at smaller addresses.
               data = symbol(&float),
               IV = symbol((&float)[stencilHeight]),
               IVSet = symbol(&float), -- IV for the set ptr
               yInLineZero = symbol(int), -- this is the Y coord of the line stored starting at address 0 in the LB. If negative LB is not yet initialized
               internal = {},
               internalVars = {}
  }


  if codegenAsFunctionCall then
    tab.internalVars.data = symbol(&&float)
    tab.internalVars.IV = symbol(& ((&float)[stencilHeight]) )
    tab.internalVars.IVSet = symbol(&&float)

    tab.internal.data = `@[tab.internalVars.data]
    tab.internal.IV = `@[tab.internalVars.IV]
    tab.internal.IVSet = `@[tab.internalVars.IVSet]

  else
    tab.internal.data = tab.data
    tab.internal.IV = tab.IV
    tab.internal.IVSet = tab.IVSet
  end

  if unrollIVLoops then
    assert(codegenAsFunctionCall==false and codegenAsLoop==false)
    tab.IV = {}
    tab.internal.IV = {}
    for i=0,stencilHeight-1 do
      tab.IV[i] = symbol(&float)
      tab.internal.IV[i] = tab.IV[i]
    end
  end


  setmetatable(tab,BufferMT)
  return tab
end

function BufferFunctions:alloc()

  local decIV

  if unrollIVLoops then
    decIV = {}
    for i=0,self.stencilHeight-1 do table.insert(decIV, quote var [self.IV[i]] end) end
  else
    decIV = quote     var [self.IV] end
  end

  return quote
    var [self.data]
    cstdlib.posix_memalign( [&&opaque](&[self.data]), pageSize, [self.lineWidth*self.stencilHeight]*sizeof(float))
    decIV
    var [self.IVSet]
    var [self.yInLineZero] = -1
  end
end

function BufferFunctions:arguments()
--  return {`@self.IV, `@self.IVSet, `@self.data}
  return {`&[self.IV], `&[self.IVSet], `&[self.data]}
--  return {self.IV, self.IVSet, self.data}
end


function BufferFunctions:formalParameters()
--  return {`&[self.IV], `&[self.IVSet], `&[self.data]}
  return {self.internalVars.IV, self.internalVars.IVSet, self.internalVars.data}
--  return {self.IV, self.IVSet, self.data}
end

function BufferFunctions:get(relX, relY)
--  if (type(relX)=="number" or terralib.issymbol(relX)) and 
--      (type(relY)=="number" or terralib.issymbol(relY)) then

    if unrollIVLoops then
      return `terralib.attrload([&vector(float,V)]([self.internal.IV[-relY]] + relX),{align=V})
    else
      return `terralib.attrload([&vector(float,V)]([self.internal.IV][-relY] + relX),{align=V})
    end

--  end
--  assert(false)
end

function BufferFunctions:set(value)
  return quote
--    [self.data][ ([self.yposSet]*[self.lineWidth]+[self.xposSet]) % [self.lineWidth*self.stencilHeight]] = value
--    cstdio.printf("SETIV\n")

--    if self.IVSet >= self.data + [self.lineWidth*self.stencilHeight]
    @[&vector(float,V)](self.internal.IVSet) = value 
end
end

function BufferFunctions:setptrPos(x,y)
  return quote
    [self.yInLineZero] = y;
    [self.IVSet] = [self.data]+x;
end

end


function BufferFunctions:getptrPos(x,y)
  assert(type(x)=="number")
  assert(type(y)=="number")

  local res = {}

  table.insert(res, quote 
--                 cstdio.printf("GET PTR POS\n")
                 if [self.yInLineZero] < 0 then cstdio.printf("LB not yet initialized\n"); cstdlib.exit(1); end end)

  -- initialize the line buffers

  if unrollIVLoops then
    for l=0,self.stencilHeight-1 do
      table.insert(res, 
                 quote
                   var fp : &float = self.data + fixedModulus((y-l-[self.yInLineZero])*[self.lineWidth]+x,[self.lineWidth*self.stencilHeight])
                   [self.IV[l]] = fp
      end)
    end
  else
    table.insert(res, 
                 quote
                   for l=0, self.stencilHeight do
                     var fp : &float = self.data + fixedModulus((y-l-[self.yInLineZero])*[self.lineWidth]+x,[self.lineWidth*self.stencilHeight])
                     [self.IV][l] = fp
                   end
    end)
  end

  return res
end

function BufferFunctions:setptrNext(V)
  --  return quote [self.xposSet] = [self.xposSet]+V; end
  return quote [self.internal.IVSet] = [self.internal.IVSet] + V; end
end

function BufferFunctions:setptrNextLine(lineWidth)
  assert(type(lineWidth)=="number")
  return quote [self.internal.IVSet] = [self.internal.IVSet] - lineWidth + [self.lineWidth]; 
    -- wrap around
    while [self.internal.IVSet] >= [self.internal.data]+[self.lineWidth*self.stencilHeight] do
      [self.internal.IVSet] = [self.internal.IVSet] - [self.lineWidth*self.stencilHeight];
---      cstdio.printf("WRAPAROUND\n");
    end
  end
end

function BufferFunctions:getptrNext(V)

  if unrollIVLoops then
    local tab = {}
    for l=0,self.stencilHeight-1 do
      table.insert(tab,quote [self.internal.IV[l]] = [self.internal.IV[l]] + V; end)
    end
    return tab
  else
    return quote
      for l = 0, [self.stencilHeight] do
        [self.internal.IV][l] = [self.internal.IV][l] + V;
      end
    end
  end
end

function BufferFunctions:getptrNextLine(lineWidth)
  assert(type(lineWidth)=="number")

  if unrollIVLoops then
    local tab = {}
    local tmp = symbol()
    table.insert(tab, quote       var [tmp] = [self.internal.IV[self.stencilHeight-1]] end)

    local l = self.stencilHeight-1
    while l>=1 do
      table.insert(tab, quote [self.internal.IV[l]] = [self.internal.IV[l-1]] - lineWidth; end)
      l = l -1
    end
    table.insert(tab, quote [self.internal.IV[0]] = tmp - lineWidth; end)

    return tab
  else
    return quote

      -- the IV that was pointing to line -4 (index 4) in the last round,
      -- should point to the line -3 (index 3) in this round
      
      var tmp = [self.internal.IV][self.stencilHeight-1]
      var l = [self.stencilHeight-1]
      while l >= 1 do
        [self.internal.IV][l] = [self.internal.IV][l-1] - lineWidth;
        l = l-1
      end
      [self.internal.IV][0] = tmp - lineWidth;
    end
  end
end
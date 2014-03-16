local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")


terra orionAssert(cond : bool, str : &int8)
  if cond==false then
    cstdio.printf("ASSERTT fail %s\n", str)
    cstdlib.exit(1)
  end
end

orion={}
orion.verbose=false
orion.tune={pageSize=4*1024*terralib.sizeof(&uint8)}

terralib.require("util")
terralib.require("image")

ImageBufferFunctions = {}
ImageBufferMT = {__index = ImageBufferFunctions}


function newImageBuffer(file)
  local tab = {file = file, 
               xposGet = symbol(int), 
               yposGet = symbol(int), 
               xposSet = symbol(int), 
               yposSet = symbol(int), 
               img=symbol(Image),
               internal={},
               internalVars = {}}

  if codegenAsFunctionCall then
    tab.internalVars.img=symbol(&Image)
    tab.internalVars.xposGet = symbol(&int)
    tab.internalVars.yposGet = symbol(&int)
    tab.internalVars.xposSet = symbol(&int)
    tab.internalVars.yposSet = symbol(&int)


    tab.internal.img= `@[tab.internalVars.img]
    tab.internal.xposGet = `@[tab.internalVars.xposGet]
    tab.internal.yposGet = `@[tab.internalVars.yposGet]
    tab.internal.xposSet = `@[tab.internalVars.xposSet]
    tab.internal.yposSet = `@[tab.internalVars.yposSet]

  else
    tab.internal.img = tab.img
    tab.internal.xposGet = tab.xposGet
    tab.internal.yposGet = tab.yposGet
    tab.internal.xposSet = tab.xposSet
    tab.internal.yposSet = tab.yposSet
  end


  return setmetatable(tab,ImageBufferMT)
end

function ImageBufferFunctions:save(file)
  return quote
    [self.img]:save(file)
end
end

function ImageBufferFunctions:toUint8()
  return quote
    [self.img]:toUint8()
end
end

function ImageBufferFunctions:arguments()
  return {`&[self.img],`&[self.xposSet], `&[self.yposSet], `&[self.xposGet], `&[self.yposGet]}
end

function ImageBufferFunctions:formalParameters()
  return {self.internalVars.img, self.internalVars.xposSet, self.internalVars.yposSet, self.internalVars.xposGet, self.internalVars.yposGet}
end

function ImageBufferFunctions:alloc()
  return quote
    var [self.img]
    [self.img]:initWithFile([self.file])

    if [self.img].width==imageSize and
      [self.img].height==imageSize and
      [self.img].channels==1 and
      [self.img].floating==false and
      [self.img].bits==8 then
      cstdio.printf("OK image format\n")

      [self.img]:toFloat32()
    else
      cstdio.printf("incorrect image format\n")
      cstdlib.exit(1)
    end

    var [self.xposSet]
    var [self.yposSet]
    var [self.xposGet]
    var [self.yposGet]

  end
end


function ImageBufferFunctions:get(relX, relY)
--  if (type(relX)=="number" or terralib.issymbol(relX)) and 
--      (type(relY)=="number" or terralib.issymbol(relY)) then
--    return `[&float]([self.img].data)[([self.yposGet]+relY)*[self.img].width+[self.xposGet]+relX]
    return `terralib.attrload([&vector(float,V)]([&float]([self.internal.img].data) + ([self.internal.yposGet]+relY)*[self.internal.img].width + [self.internal.xposGet]+relX),{align=V})
--  end
--  assert(false)
end

function ImageBufferFunctions:set(value)
  assert(terralib.isquote(value) or terralib.issymbol(value))
  return quote
--    var dst : &float = [&float]([self.img].data)
--    var addr : int = [self.yposSet]*[self.img].width+[self.xposSet]
--    dst[addr] = value
    terralib.attrstore([&vector(float,V)]([&float]([self.internal.img].data)+[self.internal.yposSet]*[self.internal.img].width+[self.internal.xposSet]),value,{nontemporal=true})
end

end


function ImageBufferFunctions:setptrPos(x,y)
  assert(type(x)=="number")
  assert(type(y)=="number")
  return quote
    [self.xposSet] = x;
    [self.yposSet] = y;
end
end

function ImageBufferFunctions:getptrPos(x,y)
  assert(type(x)=="number")
  assert(type(y)=="number")
  return quote
    [self.xposGet] = x;
    [self.yposGet] = y;
end
end


function ImageBufferFunctions:setptrNext(V)
  assert(type(V)=="number")
  return quote [self.internal.xposSet] = [self.internal.xposSet]+V; end
end

function ImageBufferFunctions:setptrNextLine(lineWidth)
  assert(type(lineWidth)=="number")
  return quote [self.internal.xposSet] = [self.internal.xposSet]-lineWidth; 
    [self.internal.yposSet] = [self.internal.yposSet] + 1;
end
end

function ImageBufferFunctions:getptrNext(V)
  assert(type(V)=="number")
  return quote [self.internal.xposGet] = [self.internal.xposGet]+V; end
end

function ImageBufferFunctions:getptrNextLine(lineWidth)
  assert(type(lineWidth)=="number")
  return quote [self.internal.xposGet] = [self.internal.xposGet]-lineWidth; 
    [self.internal.yposGet] = [self.internal.yposGet] + 1;
end
end
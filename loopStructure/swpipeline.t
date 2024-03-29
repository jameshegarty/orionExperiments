cstdio = terralib.includec("stdio.h")

local C = terralib.includecstring [[
#include <sys/time.h>
#include <stdio.h>

  double CurrentTimeInSeconds() {
  struct timeval tv;
  gettimeofday(&tv, 0);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
                                       }

                                   ]]


imageSize = 4096 -- square
stencilWidth = 4 -- square
stencilHeight = 0 -- square
stencilDepth = 10
iter = 1
codegenAsLoop = false
codegenAsFunctionCall = false
reifyBoundary = true
funroll = 8
V = 4

if reifyBoundary then
  iterationSpaceLeft = 0
  iterationSpaceRight = imageSize
  iterationSpaceBottom = 0
  iterationSpaceTop = imageSize

  interiorLeft = stencilWidth
  interiorRight = imageSize
  interiorBottom = stencilHeight
  interiorTop = imageSize
else
  assert(false)
end

--terralib.require("bufferSimple")
--terralib.require("bufferIV")
--terralib.require("fakeIV")
terralib.require("vmIV")
terralib.require("imageBufferSimple")

local y = symbol(int)
local x = symbol(int)
local allocCode = {}
local initCode = {}
local loopBoundaryCode = {}
local loopInteriorCode = {}
local endlineCode = {}
local buffer = {newImageBuffer("input.bmp")}
table.insert(allocCode,buffer[1]:alloc())
--table.insert(initCode, buffer[1]:getptrPos(stencilSize, stencilSize))

local fnc

for i=1,stencilDepth do

  local inputBuffer = buffer[i]
  local outputBuffer = newBuffer(imageSize, stencilHeight+1,i==stencilDepth)
  table.insert(buffer, outputBuffer)
  table.insert(allocCode, outputBuffer:alloc())

  table.insert(initCode,
               quote
                 [inputBuffer:getptrPos(0, 0)]
                 [outputBuffer:setptrPos(0, 0)]
                 end)

  local expr

  if codegenAsLoop then

    expr = quote
      var reduction : vector(float,V) = 0
      var A : float = 0.988
      for y = -stencilHeight,1 do
        for x = -stencilWidth,0,8 do
          reduction = reduction + (([inputBuffer:get(x,y)]*A+[inputBuffer:get(`x+1,y)]*A)+([inputBuffer:get(`x+2,y)]*A+[inputBuffer:get(`x+3,y)]*A))+(([inputBuffer:get(`x+4,y)]*A+[inputBuffer:get(`x+5,y)]*A)+([inputBuffer:get(`x+6,y)]*A+[inputBuffer:get(`x+7,y)]*A))
        end
        reduction = reduction + [inputBuffer:get(0,y)]*A
      end
      in reduction / [(stencilWidth+1)*(stencilHeight+1)] end
  else
    expr = `[vector(float,V)](0)
    for y=-stencilHeight,0 do
      for x=-stencilWidth,0 do
        expr = `expr + [inputBuffer:get(x,y)]
      end
    end
    
    expr = `expr / [(stencilWidth+1)*(stencilHeight+1)]
  end

  local loopBoundaryQuote =     quote
        [outputBuffer:set(`0)]
        [inputBuffer:getptrNext(V)]
        [outputBuffer:setptrNext(V)]
      end

  local loopInteriorQuote =     quote
        [outputBuffer:set(expr)]
        [inputBuffer:getptrNext(V)]
        [outputBuffer:setptrNext(V)]
      end

      local endlineQuote = quote
        [inputBuffer:getptrNextLine(imageSize)]
        [outputBuffer:setptrNextLine(imageSize)]
      end

  table.insert(loopInteriorCode, loopInteriorQuote)
  table.insert(loopBoundaryCode, loopBoundaryQuote)
  table.insert(endlineCode, endlineQuote)


end

-- make an image buffer to collect the output
local finalOutBuffer = newImageBuffer("input.bmp")
table.insert(allocCode, finalOutBuffer:alloc())
table.insert(initCode, quote
               [buffer[#buffer]:getptrPos(0, 0)]
               [finalOutBuffer:setptrPos(0, 0)]
               end)

table.insert(loopInteriorCode, quote
                       var expr = [buffer[#buffer]:get(0,0)]
                       [finalOutBuffer:set(expr)]
                       [buffer[#buffer]:getptrNext(V)]
                       [finalOutBuffer:setptrNext(V)]
                       end)

table.insert(loopBoundaryCode, quote
                       [finalOutBuffer:set(`0)]
                       [buffer[#buffer]:getptrNext(V)]
                       [finalOutBuffer:setptrNext(V)]
                       end)

table.insert(endlineCode, quote
                     [buffer[#buffer]:getptrNextLine(imageSize)]
                     [finalOutBuffer:setptrNextLine(imageSize)]
                     end)

local lc = {}

xi = symbol(int)
for k,v in pairs(loopInteriorCode) do
  for i=0,funroll-1 do
    table.insert(lc, quote [loopInteriorCode[k]] end)
  end
end


terra doit()
  cstdio.printf("alloc\n")
  allocCode


  var start = C.CurrentTimeInSeconds()
  for it=0,iter do
    initCode
    for [y] = iterationSpaceBottom, iterationSpaceTop do
--      cstdio.printf("Y %d\n",y)
      if y<interiorBottom or y>=interiorTop then
        for x = iterationSpaceLeft, iterationSpaceRight, V do
          loopBoundaryCode
        end
      else
        for [xi] = iterationSpaceLeft, iterationSpaceRight, V*funroll do
          if xi<interiorLeft or xi>=interiorRight then
            var rbound = interiorLeft
            if xi+V*funroll < rbound then rbound=xi+V*funroll end

            for x = xi, rbound, V do
              loopBoundaryCode
            end
            
            for x = interiorLeft, xi+funroll*V, V do
              loopInteriorCode
            end
          else
            lc
          end
        end
      end

--[=[
      for xi = iterationSpaceLeft, iterationSpaceRight, V*funroll do

        for [x] = xi,xi+funroll*V,V do
          if x<interiorLeft or x>=interiorRight or y<interiorBottom or y>=interiorTop then
            loopBoundaryCode
          else
            loopInteriorCode
          end
        end

      end
      ]=]

      endlineCode
    end
  end
  var endt = C.CurrentTimeInSeconds()

  cstdio.printf("done runtime: %f\n", (endt-start)/float(iter))

  [finalOutBuffer:toUint8()]
  [finalOutBuffer:save("output.bmp")]
end

print("FINAL COMPILE")
doit:printpretty(false)
print("PP")

start = C.CurrentTimeInSeconds()
doit:compile()
endt = C.CurrentTimeInSeconds()

doit:printpretty()
doit:disas()

print("compile time",(endt-start))

doit()

terralib.saveobj("swpipelineexec",{main = doit})

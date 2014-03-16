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
stencilSize = 16 -- square
stencilDepth = 5
iter = 3
codegenAsLoop = false
codegenAsFunctionCall = false
-- if we're codegening as a function call, we can codegen this once and call multiple times, to save compile time
dedupFunctionCalls = false
if dedupFunctionCalls then assert(codegenAsFunctionCall) end
V = 4

--terralib.require("bufferSimple")
--terralib.require("bufferIV")
terralib.require("fakeIV")
terralib.require("imageBufferSimple")

local y = symbol(int)
local allocCode = {}
local initCode = {}
local loopCode = {}
local buffer = {newImageBuffer("input.bmp")}
table.insert(allocCode,buffer[1]:alloc())
--table.insert(initCode, buffer[1]:getptrPos(stencilSize, stencilSize))

local fnc

for i=1,stencilDepth do

  local inputBuffer = buffer[i]
  local outputBuffer = newBuffer(imageSize, stencilSize,i==stencilDepth)
  table.insert(buffer, outputBuffer)
  table.insert(allocCode, outputBuffer:alloc())

  table.insert(initCode,
               quote
                 [inputBuffer:getptrPos(stencilSize,stencilSize)]
                 [outputBuffer:setptrPos(stencilSize,stencilSize)]
                 end)

  local expr

  if codegenAsLoop then

    expr = quote
      var reduction : vector(float,V) = 0
      for x = -stencilSize+1,1 do
        for y = -stencilSize+1,1 do
          reduction = reduction + [inputBuffer:get(x,y)]
        end
      end
      in reduction / [stencilSize*stencilSize] end
  else
    expr = `[vector(float,V)](0)
    for x=-stencilSize+1,0 do
      for y=-stencilSize+1,0 do
        expr = `expr + [inputBuffer:get(x,y)]
      end
    end
    
    expr = `expr / [stencilSize*stencilSize]
  end

  local loopQuote =     quote
      for x = stencilSize, imageSize, V do
        [outputBuffer:set(expr)]
        [inputBuffer:getptrNext(V)]
        [outputBuffer:setptrNext(V)]
      end
      [inputBuffer:getptrNextLine(imageSize-stencilSize)]
      [outputBuffer:setptrNextLine(imageSize-stencilSize)]
      end

  if codegenAsFunctionCall then
    if dedupFunctionCalls==false or i<=2 then
      fnc = terra([inputBuffer:formalParameters()],[outputBuffer:formalParameters()])
        loopQuote
      end
    end
--    fnc:printpretty()
--    fnc:disas()
    table.insert(loopCode, quote fnc([inputBuffer:arguments()],[outputBuffer:arguments()]) end)
  else
    table.insert(loopCode, loopQuote)
  end

end

-- make an image buffer to collect the output
local finalOutBuffer = newImageBuffer("input.bmp")
table.insert(allocCode, finalOutBuffer:alloc())
table.insert(initCode, quote
               [buffer[#buffer]:getptrPos(stencilSize, stencilSize)]
               [finalOutBuffer:setptrPos(stencilSize,stencilSize)]
               end)

local loopQuote = quote
                     for x = stencilSize, imageSize, V do
                       var expr = [buffer[#buffer]:get(0,0)]
                       [finalOutBuffer:set(expr)]
                       [buffer[#buffer]:getptrNext(V)]
                       [finalOutBuffer:setptrNext(V)]
                     end
                     [buffer[#buffer]:getptrNextLine(imageSize-stencilSize)]
                     [finalOutBuffer:setptrNextLine(imageSize-stencilSize)]
                     end

if codegenAsFunctionCall then
  local terra fnc([buffer[#buffer]:formalParameters()],[finalOutBuffer:formalParameters()])
    loopQuote
  end
  table.insert(loopCode, quote fnc([buffer[#buffer]:arguments()],[finalOutBuffer:arguments()]) end)
else
  table.insert(loopCode, loopQuote)
end




terra doit()
  cstdio.printf("alloc\n")
  allocCode

  var start = C.CurrentTimeInSeconds()
  for i=0,iter do
    cstdio.printf("init\n")
    initCode
    for [y] = stencilSize, imageSize do
--      cstdio.printf("Y %d\n",y)
      loopCode
--      cstdio.printf("YD\n")
    end
  end
  var endt = C.CurrentTimeInSeconds()

  cstdio.printf("done runtime: %f\n", (endt-start)/float(iter))

  [finalOutBuffer:toUint8()]
  [finalOutBuffer:save("output.bmp")]
end

start = C.CurrentTimeInSeconds()
doit:compile()
endt = C.CurrentTimeInSeconds()

doit:printpretty()

print("compile time",(endt-start))

doit()
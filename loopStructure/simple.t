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
stencilDepth = 10
iter = 3
codegenAsSerial = false
codegenAsLoop = true
codegenAsFunctionCall = false
-- if we're codegening as a function call, we can codegen this once and call multiple times, to save compile time
dedupFunctionCalls = false
if dedupFunctionCalls then assert(codegenAsFunctionCall) end
V = 4

--terralib.require("bufferSimple")
--terralib.require("bufferIV")
terralib.require("fakeIV")
--terralib.require("vmIV")
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
                 [inputBuffer:getptrPos(0, 0)]
                 [outputBuffer:setptrPos(0, 0)]
                 end)

  local expr

  if codegenAsSerial then
    expr = quote
      var reduction : vector(float,V) = 0
      var A : float = 0.988
      for y = -stencilSize+1,1 do
        reduction = reduction - [inputBuffer:get(-stencilSize,y)]*A
      end
      for y = -stencilSize+1,1 do
        reduction = reduction + [inputBuffer:get(0,y)]*A
      end
      in [inputBuffer:getSet(-V)] + (reduction / [stencilSize*stencilSize]) end
  elseif codegenAsLoop then

--[=[
    expr = quote
      var reduction : vector(float,V) = 0
      for y = -stencilSize+1,1 do
        for x = -stencilSize+1,1 do
          reduction = reduction + [inputBuffer:get(x,y)]
        end
      end
      in reduction / [stencilSize*stencilSize] end
  ]=]
    expr = quote
      var reduction : vector(float,V) = 0
      var A : float = 0.988
      for y = -stencilSize+1,1 do
--        for x = -stencilSize+1,1 do
--          reduction = reduction + [inputBuffer:get(x,y)]*A
--        end

        for x = -stencilSize+1,1,8 do
          reduction = reduction + (([inputBuffer:get(x,y)]*A+[inputBuffer:get(`x+1,y)]*A)+([inputBuffer:get(`x+2,y)]*A+[inputBuffer:get(`x+3,y)]*A))+(([inputBuffer:get(`x+4,y)]*A+[inputBuffer:get(`x+5,y)]*A)+([inputBuffer:get(`x+6,y)]*A+[inputBuffer:get(`x+7,y)]*A))
        end

--          var x = -stencilSize+1
--          reduction = reduction + ((([inputBuffer:get(x,y)]+[inputBuffer:get(`x+1,y)])+([inputBuffer:get(`x+2,y)]+[inputBuffer:get(`x+3,y)]))+(([inputBuffer:get(`x+4,y)]+[inputBuffer:get(`x+5,y)])+([inputBuffer:get(`x+6,y)]+[inputBuffer:get(`x+7,y)])))+((([inputBuffer:get(`x+8,y)]+[inputBuffer:get(`x+9,y)])+([inputBuffer:get(`x+10,y)]+[inputBuffer:get(`x+11,y)]))+(([inputBuffer:get(`x+12,y)]+[inputBuffer:get(`x+13,y)])+([inputBuffer:get(`x+14,y)]+[inputBuffer:get(`x+16,y)])))
      end
      in reduction / [stencilSize*stencilSize] end
  else
    expr = `[vector(float,V)](0)
    for y=-stencilSize+1,0 do
      for x=-stencilSize+1,0 do
        expr = `expr + [inputBuffer:get(x,y)]
      end
    end
    
    expr = `expr / [stencilSize*stencilSize]
  end

  local loopQuote =     quote
  if y<stencilSize then
                     for x = 0, imageSize, V do
        [outputBuffer:set(`0)]
        [inputBuffer:getptrNext(V)]
        [outputBuffer:setptrNext(V)]
                     end

else

      for x = 0, stencilSize, V do
        [outputBuffer:set(`0)]
        [inputBuffer:getptrNext(V)]
        [outputBuffer:setptrNext(V)]
      end

      for x = stencilSize, imageSize, V do
        [outputBuffer:set(expr)]
        [inputBuffer:getptrNext(V)]
        [outputBuffer:setptrNext(V)]
      end
end
      [inputBuffer:getptrNextLine(imageSize)]
      [outputBuffer:setptrNextLine(imageSize)]
      end

  if codegenAsFunctionCall then
    if dedupFunctionCalls==false or i<=2 then
      fnc = terra([inputBuffer:formalParameters()],[outputBuffer:formalParameters()])
        loopQuote
      end
      fnc:printpretty()
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
               [buffer[#buffer]:getptrPos(0, 0)]
               [finalOutBuffer:setptrPos(0,0)]
               end)

local loopQuote = quote
  if y<stencilSize then
                     for x = 0, imageSize, V do
                       [finalOutBuffer:set(`0)]
                       [buffer[#buffer]:getptrNext(V)]
                       [finalOutBuffer:setptrNext(V)]
                     end

else
                     for x = 0, stencilSize, V do
                       [finalOutBuffer:set(`0)]
                       [buffer[#buffer]:getptrNext(V)]
                       [finalOutBuffer:setptrNext(V)]
                     end

                     for x = stencilSize, imageSize, V do
                       var expr = [buffer[#buffer]:get(0,0)]
                       [finalOutBuffer:set(expr)]
                       [buffer[#buffer]:getptrNext(V)]
                       [finalOutBuffer:setptrNext(V)]
                     end
end
                     [buffer[#buffer]:getptrNextLine(imageSize)]
                     [finalOutBuffer:setptrNextLine(imageSize)]
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
    initCode
    for [y] = 0, imageSize do
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

print("FINAL COMPILE")
doit:printpretty(false)
print("PP")

start = C.CurrentTimeInSeconds()
doit:compile()
endt = C.CurrentTimeInSeconds()

doit:printpretty()

print("compile time",(endt-start))

doit()
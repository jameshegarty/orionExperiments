local C = terralib.includecstring [[
#include <sys/time.h>
#include <stdio.h>

  double CurrentTimeInSeconds() {
  struct timeval tv;
  gettimeofday(&tv, 0);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
                                       }

                                   ]]

imageSize = 64*1024*1024 -- make sure this thing falls out of cache
stencilSize = 1024
stencilDepth = 3
iter = 3

terralib.require("bufferSimple")

local x = symbol(int)
local loopCode = {}
local buffer = {newBuffer(imageSize, stencilSize)} -- we will init this at the start
local allocCode = {}

for i=1,stencilDepth do
  table.insert(loopCode, quote
end)
end


terra doit()
  allocCode

  -- initialize the first buffer
  for x = 0, imageSize do
    [buffer[1]:set(x,vectorof(float,1,1,1,1))]
  end
  
  var start = C.CurrentTimeInSeconds()
  for i=0,iter do
    for [x] = stencilSize, imageSize do
      loopCode
    end
  end
  var endt = C.CurrentTimeInSeconds()

  cstdio.printf("done runtime: %f trafficGB:%d\n", (endt-start)/float(iter),imageSizeMB)

end

doit()
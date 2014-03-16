import "orion"

inp = orion.load("input.bmp")

local C = terralib.includecstring [[
#include <sys/time.h>
#include <stdio.h>

  double CTIS() {
  struct timeval tv;
  gettimeofday(&tv, 0);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
                                       }

                                   ]]


stencilSize = 16
stencilDepth = 5
iter = 3
serialReduce = true

for i=1,stencilDepth do

  if serialReduce then
    local tmp = im(x,y) : cropNone, float32 0 end
    for i=-stencilSize+1,0 do
      for j=-stencilSize+1,0 do
        tmp = im(x,y) : cropNone, float32 tmp + inp(x+i,y+j) end
      end
    end

    inp = im(x,y) tmp / [stencilSize*stencilSize] end
  else
    local tmp = {}
    for i=-stencilSize+1,0 do
      for j=-stencilSize+1,0 do
        table.insert(tmp,im(x,y) : cropNone, float32 inp(x+i,y+j) end)
      end
    end
    inp = im(x,y) [orion.sum(tmp[1],unpack(tmp))] / [stencilSize*stencilSize] end
  end
end

func = orion.compile({inp},{schedule="linebufferall", debug=false})

terra doit()
  var start = C.CTIS()
  var outp = func()
  for i=1,iter do
    cstdio.printf("iter\n")
    outp = func()
  end
  var endt = C.CTIS()

  cstdio.printf("done runtime: %f\n", (endt-start)/float(iter))
  outp:toUint8()
  outp:save("outputOrion.bmp")
end

doit()
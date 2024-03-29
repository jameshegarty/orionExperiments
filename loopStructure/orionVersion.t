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


stencilWidth = 16
stencilHeight = 16
stencilDepth = 10
iter = 3
serialReduce = false
A = 0.988

for i=1,stencilDepth do

  if serialReduce then
    local tmp = im(x,y) : cropNone, float32 0 end

    for j=-stencilHeight,0 do
      for i=-stencilWidth,0 do
        tmp = im(x,y) : cropNone, float32 tmp + inp(x+i,y+j)*A end
      end
    end

    inp = im(x,y) : crop(16,16,4080,4080)  tmp / [(stencilWidth+1)*(stencilHeight+1)] end
  else
    local tmp = {}

    for j=-stencilHeight,0 do
        for i=-stencilWidth,0 do
        table.insert(tmp,im(x,y) : cropNone, float32 inp(x+i,y+j)*A end)
      end
    end
    inp = im(x,y) : crop(16,16,4080,4080) [orion.sum(tmp[1],unpack(tmp))] / [(stencilWidth+1)*(stencilHeight+1)] end
  end
end

func = orion.compile({inp},{schedule="materialize", debug=false, printstage = true, region="centered"})

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
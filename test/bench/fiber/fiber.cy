var Root.count = 0

func inc():
    count += 1
    coyield
    count += 1

var fibers = []
for 0..100000:
    var f = coinit(inc)
    coresume f
    fibers.append(f)

for fibers -> f:
    coresume f

print(count)

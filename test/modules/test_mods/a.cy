var .varInt = 123
var .varTypedInt int = 123
var .varAny = [1, 2, 3]
var .varList List = [1, 2, 3]
var .varMap Map = [a: 1, b: 2, c: 3]
var .varFunc = func():
    return 345
var .varFunc1 = func(a):
    return a + 1
var .varFunc2 = func(a, b):
    return a + b

var .varNoExport = 123

func fn():
    return 234
func fn1(a):
    return a + 1
func fn2(a, b):
    return a + b

func barNoExport():
    return 234

-- Test that there is no main block execution for imported modules.
panic(.ExecutedModuleMain)

func toInt(val) int:
    return int(val)

var .initOnce = incInitOnce(initOnceCount)
var .initOnceCount = 0
func incInitOnce(cur):
    initOnceCount = cur + 1
    return initOnceCount

-- Tests dependency generation, so set resulting symbol's natural order before the dependency.
var .varDepRes = varDep
var .varDep = 123

func sameFuncName():
    return 123

func useInt(a):
    return toInt(a)

type Vec2:
    var x float
    var y float

func Vec2.new(x float, y float):
    return [Vec2 x: x, y: y]
type Vec2Alias Vec2

type Bar:
    var a float
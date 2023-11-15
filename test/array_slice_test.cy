-- Copyright (c) 2023 Cyber (See LICENSE)

-- Same tests as array.cy except using a slice.

import t 'test'

var arr = array('abc🦊xyz🐶')
arr = arr[0..]  -- Sets up the slice.
t.eq(arr, array('abc🦊xyz🐶'))

-- Sets up the slice
var upper = array('ABC🦊XYZ🐶')[0..]

-- index operator
t.eq(arr[-1], 182)
t.eq(arr[-4], 240)
t.eq(arr[0], 97)
t.eq(arr[3], 240)
t.eq(try arr[14], error.OutOfBounds)

-- slice operator
t.eq(arr[0..], array('abc🦊xyz🐶'))
t.eq(arr[7..], array('xyz🐶'))
t.eq(arr[10..], array('🐶'))
t.eq(try arr[-1..], error.OutOfBounds)
t.eq(try arr[..-1], error.OutOfBounds)
t.eq(try arr[15..], error.OutOfBounds)
t.eq(try arr[..15], error.OutOfBounds)
t.eq(try arr[14..15], error.OutOfBounds)
t.eq(try arr[3..1], error.OutOfBounds)
t.eq(arr[14..], array(''))
t.eq(arr[..0], array(''))
t.eq(arr[..7], array('abc🦊'))
t.eq(arr[..10], array('abc🦊xyz'))
t.eq(arr[..14], array('abc🦊xyz🐶'))
t.eq(arr[0..0], array(''))
t.eq(arr[0..1], array('a'))
t.eq(arr[7..14], array('xyz🐶'))
t.eq(arr[10..14], array('🐶'))
t.eq(arr[14..14], array(''))

-- byteAt()
t.eq(arr.byteAt(-1), 182)
t.eq(arr.byteAt(0), 97)
t.eq(arr.byteAt(3), 240)
t.eq(arr.byteAt(4), 159)
t.eq(arr.byteAt(10), 240)
t.eq(arr.byteAt(13), 182)
t.eq(try arr.byteAt(14), error.OutOfBounds)

-- concat()
t.eq(arr.concat(array('123')), array('abc🦊xyz🐶123'))

-- decode()
t.eq(arr.decode(), 'abc🦊xyz🐶')
t.eq(arr.decode().isAscii(), false)
t.eq(array('abc').decode(), 'abc')
t.eq(array('abc').decode().isAscii(), true)
t.eq(try array('').insertByte(0, 255).decode(), error.Unicode)

-- endsWith()
t.eq(arr.endsWith(array('xyz🐶')), true)
t.eq(arr.endsWith(array('xyz')), false)

-- find()
t.eq(arr.find(array('bc🦊')), 1)
t.eq(arr.find(array('xy')), 7)
t.eq(arr.find(array('bd')), none)
t.eq(arr.find(array('ab')), 0)

-- findAnyByte()
t.eq(arr.findAnyByte(array('a')), 0)
t.eq(arr.findAnyByte(array('xy')), 7)
t.eq(arr.findAnyByte(array('ef')), none)

-- findByte()
t.eq(arr.findByte(0u'a'), 0)
t.eq(arr.findByte(0u'x'), 7)
t.eq(arr.findByte(0u'd'), none)
t.eq(arr.findByte(97), 0)
t.eq(arr.findByte(100), none)

-- insertByte()
t.eq(arr.insertByte(2, 97), array('abac🦊xyz🐶'))

-- insert()
t.eq(try arr.insert(-1, array('foo')), error.OutOfBounds)
t.eq(arr.insert(0, array('foo')), array('fooabc🦊xyz🐶'))
t.eq(arr.insert(3, array('foo🦊')), array('abcfoo🦊🦊xyz🐶'))
t.eq(arr.insert(10, array('foo')), array('abc🦊xyzfoo🐶'))
t.eq(arr.insert(14, array('foo')), array('abc🦊xyz🐶foo'))
t.eq(try arr.insert(15, array('foo')), error.OutOfBounds)

-- len()
t.eq(arr.len(), 14)

-- repeat()
t.eq(try arr.repeat(-1), error.InvalidArgument)
t.eq(arr.repeat(0), array(''))
t.eq(arr.repeat(1), array('abc🦊xyz🐶'))
t.eq(arr.repeat(2), array('abc🦊xyz🐶abc🦊xyz🐶'))

-- replace()
t.eq(arr.replace(array('abc🦊'), array('foo')), array('fooxyz🐶'))
t.eq(arr.replace(array('bc🦊'), array('foo')), array('afooxyz🐶'))
t.eq(arr.replace(array('bc'), array('foo🦊')), array('afoo🦊🦊xyz🐶'))
t.eq(arr.replace(array('xy'), array('foo')), array('abc🦊fooz🐶'))
t.eq(arr.replace(array('xyz🐶'), array('foo')), array('abc🦊foo'))
t.eq(arr.replace(array('abcd'), array('foo')), array('abc🦊xyz🐶'))

-- split()
var res = array('abc,🐶ab,a')[0..].split(array(','))
t.eq(res.len(), 3)
t.eq(res[0], array('abc'))
t.eq(res[1], array('🐶ab'))
t.eq(res[2], array('a'))

-- trim()
t.eq(arr.trim(.left, array('a')), array('bc🦊xyz🐶'))
t.eq(arr.trim(.right, array('🐶')), array('abc🦊xyz'))
t.eq(arr.trim(.ends, array('a🐶')), array('bc🦊xyz'))

-- startsWith()
t.eq(arr.startsWith(array('abc🦊')), true)
t.eq(arr.startsWith(array('bc🦊')), false)
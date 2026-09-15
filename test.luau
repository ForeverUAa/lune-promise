local Promise = require("./lib")
local task = require("@lune/task")

print("A")

Promise.resolve("hello")
	:andThen(function(value)
		print("RESOLVED:", value)
	end)

print("B")

task.wait(0.1)

print("C")
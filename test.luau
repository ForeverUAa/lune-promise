local Promise = require("./lib")
local process = require("@lune/process")
local task = require("@lune/task")

local passed = 0
local failed = 0

local function test(name, callback)
	local ok, err = xpcall(callback, debug.traceback)

	if ok then
		passed += 1
		print("PASS:", name)
	else
		failed += 1
		warn("FAIL:", name)
		warn(err)
	end
end

local function expectEqual(actual, expected, message)
	assert(actual == expected, message or string.format(
		"expected %s, got %s",
		tostring(expected),
		tostring(actual)
	))
end

task.spawn(function()
	print("=== Promise Lune test suite ===")
	print("")

	-- Basic construction / resolution
	test("Promise.resolve", function()
		local status, value = Promise.resolve("hello"):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "hello")
	end)

	test("Promise.resolve multiple values", function()
		local status, a, b, c = Promise.resolve(1, 2, 3):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(a, 1)
		expectEqual(b, 2)
		expectEqual(c, 3)
	end)

	test("Promise.new resolves", function()
		local status, value = Promise.new(function(resolve)
			resolve(123)
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 123)
	end)

	test("Promise.new executor may yield", function()
		local status, value = Promise.new(function(resolve)
			task.wait(0.02)
			resolve("yielded")
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "yielded")
	end)

	-- Chaining
	test("andThen transforms value", function()
		local status, value = Promise.resolve(10)
			:andThen(function(x)
				return x * 2
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 20)
	end)

	test("andThen chains multiple times", function()
		local status, value = Promise.resolve(5)
			:andThen(function(x)
				return x + 5
			end)
			:andThen(function(x)
				return x * 2
			end)
			:andThen(function(x)
				return x - 3
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 17)
	end)

	test("andThen can return a Promise", function()
		local status, value = Promise.resolve(10)
			:andThen(function(x)
				return Promise.resolve(x * 3)
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 30)
	end)

	test("andThen rejection handler", function()
		local status, value = Promise.reject("bad")
			:andThen(nil, function(err)
				return "recovered: " .. err
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "recovered: bad")
	end)

	-- Rejection
	test("Promise.reject", function()
		local status, reason = Promise.reject("boom"):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		expectEqual(reason, "boom")
	end)

	test("catch recovers", function()
		local status, value = Promise.reject("boom")
			:catch(function(err)
				return "caught: " .. err
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "caught: boom")
	end)

	test("executor error becomes rejection", function()
		local status, err = Promise.new(function()
			error("executor exploded")
		end):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		assert(Promise.Error.is(err), "expected Promise.Error")
		expectEqual(err.kind, Promise.Error.Kind.ExecutionError)
	end)

	test("andThen error becomes rejection", function()
		local status, err = Promise.resolve()
			:andThen(function()
				error("callback exploded")
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		assert(Promise.Error.is(err), "expected Promise.Error")
		expectEqual(err.kind, Promise.Error.Kind.ExecutionError)
	end)

	-- finally / tap
	test("finally runs on resolve", function()
		local called = false

		local status, value = Promise.resolve(42)
			:finally(function()
				called = true
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 42)
		assert(called, "finally was not called")
	end)

	test("finally runs on reject", function()
		local called = false

		local status, reason = Promise.reject("bad")
			:finally(function()
				called = true
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		expectEqual(reason, "bad")
		assert(called, "finally was not called")
	end)

	test("finally can return a Promise", function()
		local status, value = Promise.resolve("hello")
			:finally(function()
				return Promise.delay(0.01)
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "hello")
	end)

	test("tap preserves value", function()
		local seen

		local status, value = Promise.resolve(99)
			:tap(function(x)
				seen = x
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 99)
		expectEqual(seen, 99)
	end)

	-- Delay / defer
	test("Promise.delay", function()
		local start = os.clock()

		local status, value = Promise.delay(0.03)
			:andThen(function()
				return "done"
			end)
			:awaitStatus()

		local elapsed = os.clock() - start

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "done")
		assert(elapsed >= 0.02, "delay completed too early")
	end)

	test("Promise.defer", function()
		local ran = false

		local promise = Promise.defer(function(resolve)
			ran = true
			resolve("deferred")
		end)

		assert(not ran, "defer executed synchronously")

		local status, value = promise:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "deferred")
		assert(ran, "deferred executor never ran")
	end)

	-- all
	test("Promise.all", function()
		local status, values = Promise.all({
			Promise.resolve(1),
			Promise.resolve(2),
			Promise.resolve(3),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)

		expectEqual(#values, 3)
		expectEqual(values[1], 1)
		expectEqual(values[2], 2)
		expectEqual(values[3], 3)
	end)

	test("Promise.all preserves order", function()
		local status, values = Promise.all({
			Promise.delay(0.03):andThen(function()
				return "slow"
			end),

			Promise.resolve("fast"),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(values[1], "slow")
		expectEqual(values[2], "fast")
	end)

	test("Promise.all rejects", function()
		local status, reason = Promise.all({
			Promise.resolve(1),
			Promise.reject("failed"),
			Promise.resolve(3),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		expectEqual(reason, "failed")
	end)

	-- race / any / some
	test("Promise.race", function()
		local status, value = Promise.race({
			Promise.delay(0.03):andThen(function()
				return "slow"
			end),

			Promise.resolve("fast"),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "fast")
	end)

	test("Promise.any", function()
		local status, value = Promise.any({
			Promise.reject("first"),
			Promise.resolve("winner"),
			Promise.delay(0.02),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "winner")
	end)

	test("Promise.some", function()
		local status, values = Promise.some({
			Promise.resolve(1),
			Promise.resolve(2),
			Promise.resolve(3),
		}, 2):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(#values, 2)
	end)

	-- each / fold
	test("Promise.each", function()
		local seen = {}

		local status, values = Promise.each({
			Promise.resolve(1),
			Promise.resolve(2),
			Promise.resolve(3),
		}, function(value)
			table.insert(seen, value * 2)
			return value * 2
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(#values, 3)

		expectEqual(seen[1], 2)
		expectEqual(seen[2], 4)
		expectEqual(seen[3], 6)

		expectEqual(values[1], 2)
		expectEqual(values[2], 4)
		expectEqual(values[3], 6)
	end)

	test("Promise.fold", function()
		local status, value = Promise.fold({
			1,
			2,
			3,
			4,
		}, function(accumulator, current)
			return accumulator + current
		end, 0):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 10)
	end)

	-- cancellation
	test("cancel pending Promise", function()
		local ran = false

		local promise = Promise.new(function(resolve, _, onCancel)
			local cancelled = false

			onCancel(function()
				cancelled = true
			end)

			task.wait(0.05)

			if not cancelled then
				ran = true
				resolve("bad")
			end
		end)

		promise:cancel()

		expectEqual(promise:getStatus(), Promise.Status.Cancelled)

		task.wait(0.08)

		assert(not ran, "cancelled Promise continued execution")
	end)

	test("cancel hook runs", function()
		local cancelled = false

		local promise = Promise.new(function(_, _, onCancel)
			onCancel(function()
				cancelled = true
			end)

			process.exit(failed > 0 and 1 or 0)
		end)

		promise:cancel()

		task.wait(0.01)

		assert(cancelled, "cancellation hook did not run")
	end)

	test("cancel resolved Promise does nothing", function()
		local promise = Promise.resolve("done")

		promise:cancel()

		expectEqual(promise:getStatus(), Promise.Status.Resolved)
	end)

	-- Status / helpers
	test("getStatus", function()
		local promise = Promise.resolve(1)

		expectEqual(promise:getStatus(), Promise.Status.Resolved)
	end)

	test("_unwrap resolved", function()
		local success, value = Promise.resolve(123):_unwrap()

		assert(success, "expected success")
		expectEqual(value, 123)
	end)

	test("Promise.is", function()
		local promise = Promise.resolve(1)

		assert(Promise.is(promise), "Promise.is returned false")
		assert(not Promise.is(123), "Promise.is returned true for number")
		assert(not Promise.is({}), "Promise.is returned true for table")
	end)

	test("Promise.try", function()
		local status, value = Promise.try(function()
			return 10 + 20
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 30)
	end)

	test("Promise.try catches errors", function()
		local status, err = Promise.try(function()
			error("try failed")
		end):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		assert(Promise.Error.is(err), "expected Promise.Error")
	end)

	-- Nested / concurrent execution
	test("concurrent Promises", function()
		local status, values = Promise.all({
			Promise.delay(0.02):andThen(function()
				return "A"
			end),

			Promise.delay(0.01):andThen(function()
				return "B"
			end),

			Promise.resolve("C"),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)

		expectEqual(values[1], "A")
		expectEqual(values[2], "B")
		expectEqual(values[3], "C")
	end)

	test("nested Promise chain", function()
		local status, value = Promise.resolve(2)
			:andThen(function(x)
				return Promise.new(function(resolve)
					task.wait(0.01)
					resolve(x * 3)
				end)
			end)
			:andThen(function(x)
				return x + 4
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 10)
	end)

	print("")
	print(string.format("=== %d passed, %d failed ===", passed, failed))

	if failed > 0 then
		error(string.format("%d Promise tests failed", failed))
	else
		print("ALL TESTS PASSED")
	end
end)

task.wait(1)
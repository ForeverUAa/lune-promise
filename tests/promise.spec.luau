--!strict
local Lest = require("../.lest/core")
local describe, it, expect = Lest.describe, Lest.it, Lest.expect

local Promise = require("../lib")
local task = require("@lune/task")

local function expectEqual(actual, expected, message)
	assert(actual == expected, message or string.format(
		"expected %s, got %s",
		tostring(expected),
		tostring(actual)
	))
end


describe("Promise", function()

	-- Basic construction / resolution
	it("Promise.resolve", function()
		local status, value = Promise.resolve("hello"):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "hello")
	end)

	it("Promise.resolve multiple values", function()
		local status, a, b, c = Promise.resolve(1, 2, 3):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(a, 1)
		expectEqual(b, 2)
		expectEqual(c, 3)
	end)

	it("Promise.new resolves", function()
		local status, value = Promise.new(function(resolve)
			resolve(123)
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 123)
	end)

	it("Promise.new executor may yield", function()
		local status, value = Promise.new(function(resolve)
			task.wait(0.02)
			resolve("yielded")
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "yielded")
	end)

	-- Chaining
	it("andThen transforms value", function()
		local status, value = Promise.resolve(10)
			:andThen(function(x)
				return x * 2
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 20)
	end)

	it("andThen chains multiple times", function()
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

	it("andThen can return a Promise", function()
		local status, value = Promise.resolve(10)
			:andThen(function(x)
				return Promise.resolve(x * 3)
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 30)
	end)

	it("andThen rejection handler", function()
		local status, value = Promise.reject("bad")
			:andThen(nil, function(err)
				return "recovered: " .. err
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "recovered: bad")
	end)

	-- Rejection
	it("Promise.reject", function()
		local status, reason = Promise.reject("boom"):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		expectEqual(reason, "boom")
	end)

	it("catch recovers", function()
		local status, value = Promise.reject("boom")
			:catch(function(err)
				return "caught: " .. err
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "caught: boom")
	end)

	it("executor error becomes rejection", function()
		local status, err = Promise.new(function()
			error("executor exploded")
		end):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		assert(Promise.Error.is(err), "expected Promise.Error")
		expectEqual(err.kind, Promise.Error.Kind.ExecutionError)
	end)

	it("andThen error becomes rejection", function()
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
	it("finally runs on resolve", function()
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

	it("finally runs on reject", function()
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

	it("finally can return a Promise", function()
		local status, value = Promise.resolve("hello")
			:finally(function()
				return Promise.delay(0.01)
			end)
			:awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "hello")
	end)

	it("tap preserves value", function()
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
	it("Promise.delay", function()
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

	it("Promise.defer", function()
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
	it("Promise.all", function()
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

	it("Promise.all preserves order", function()
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

	it("Promise.all rejects", function()
		local status, reason = Promise.all({
			Promise.resolve(1),
			Promise.reject("failed"),
			Promise.resolve(3),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		expectEqual(reason, "failed")
	end)

	-- race / any / some
	it("Promise.race", function()
		local status, value = Promise.race({
			Promise.delay(0.03):andThen(function()
				return "slow"
			end),

			Promise.resolve("fast"),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "fast")
	end)

	it("Promise.any", function()
		local status, value = Promise.any({
			Promise.reject("first"),
			Promise.resolve("winner"),
			Promise.delay(0.02),
		}):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, "winner")
	end)

	it("Promise.some", function()
		local status, values = Promise.some({
			Promise.resolve(1),
			Promise.resolve(2),
			Promise.resolve(3),
		}, 2):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(#values, 2)
	end)

	-- each / fold
	it("Promise.each", function()
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

	it("Promise.fold", function()
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
	it("cancel pending Promise", function()
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

	it("cancel hook runs", function()
		local cancelled = false

		local promise = Promise.new(function(_, _, onCancel)
			onCancel(function()
				cancelled = true
			end)

			task.wait(0.05)
		end)

		promise:cancel()

		task.wait(0.01)

		assert(cancelled, "cancellation hook did not run")
	end)

	it("cancel resolved Promise does nothing", function()
		local promise = Promise.resolve("done")

		promise:cancel()

		expectEqual(promise:getStatus(), Promise.Status.Resolved)
	end)

	-- Regression / edge cases
	it("Error.new uses fallback error text", function()
		local err = Promise.Error.new()

		expectEqual(err.error, "[This error has no error text.]")
	end)

	it("Promise.defer can be cancelled before executor starts", function()
		local ran = false

		local promise = Promise.defer(function()
			ran = true
		end)

		promise:cancel()
		expectEqual(promise:getStatus(), Promise.Status.Cancelled)

		task.wait(0.02)
		assert(not ran, "cancelled deferred executor still ran")
	end)

	it("Promise.defer executor runs exactly once", function()
		local runs = 0

		local status = Promise.defer(function(resolve)
			runs += 1
			resolve("ok")
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(runs, 1)
	end)

	-- Status / helpers
	it("getStatus", function()
		local promise = Promise.resolve(1)

		expectEqual(promise:getStatus(), Promise.Status.Resolved)
	end)

	it("_unwrap resolved", function()
		local success, value = Promise.resolve(123):_unwrap()

		assert(success, "expected success")
		expectEqual(value, 123)
	end)

	it("Promise.is", function()
		local promise = Promise.resolve(1)

		assert(Promise.is(promise), "Promise.is returned false")
		assert(not Promise.is(123), "Promise.is returned true for number")
		assert(not Promise.is({}), "Promise.is returned true for table")
	end)

	it("Promise.try", function()
		local status, value = Promise.try(function()
			return 10 + 20
		end):awaitStatus()

		expectEqual(status, Promise.Status.Resolved)
		expectEqual(value, 30)
	end)

	it("Promise.try catches errors", function()
		local status, err = Promise.try(function()
			error("try failed")
		end):awaitStatus()

		expectEqual(status, Promise.Status.Rejected)
		assert(Promise.Error.is(err), "expected Promise.Error")
	end)

	-- Nested / concurrent execution
	it("concurrent Promises", function()
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

	it("nested Promise chain", function()
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

end)

return nil

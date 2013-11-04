# Lockstep

Tools for testing thread-aware code without actually using threads.

## Synopsis

From the [Tapas::Queue](https://github.com/avdi/tapas-queue) test suite:

```ruby
require "spec_helper"
require "tapas/queue"
require "timeout"
require "lockstep"

include Lockstep

module Tapas
  describe Queue do
    # ...

    class FakeCondition
      def wait(timeout)
        SyncThread.interrupt(self, :wait, timeout)
      end
      def signal
        SyncThread.interrupt(self, :signal)
      end
    end

    class FakeLock
      def synchronize
        yield
      end
    end

    specify "waiting to push" do
      producer = SyncThread.new
      consumer = SyncThread.new
      q = Queue.new(3,
        lock: FakeLock.new,
        space_available_condition: space_available = FakeCondition.new,
        item_available_condition:  item_available = FakeCondition.new)
      producer.run(ignore: [:signal]) do
        3.times do |n|
          q.push "item #{n+1}"
        end
      end
      expect(producer).to be_finished
      producer.run(ignore: [:signal]) do
        q.push "item 4"
      end
      expect(producer).to be_interrupted_by(space_available, :wait)
      consumer.run do
        q.pop
      end
      expect(consumer).to be_interrupted_by(space_available, :signal)
      consumer.finish
      expect(producer.resume(ignore: [:signal])).to be_finished
      consumer.run(ignore: [:signal]) do
        3.times.map { q.pop }
      end
      expect(consumer.last_return_value).to eq(["item 2", "item 3", "item 4"])
    end

    def wait_for
      Timeout.timeout 1 do
        sleep 0.001 until yield
      end
    end
  end
end
```

## Huh?

`SyncThread` can run arbitrary code within the context of a `Fiber`. Sending the `.interrupt` message returns control back to the test code early, along with information about what interrupted the execution. Some handy predicates are exposed to make it easy to make assertions about what happened during the last slice of fake thread execution.

`Lockstep` does **not** stub out the behavior of Ruby threading primitives like `Mutex` and `ConditionVariable` for you. It is up to you to ensure that the code under test sends `SyncThread.interrupt` when it would ordinarily invoke a blocking system call. A recommended way to do this is to separate your logic from its interaction with the system using injectable [adapters](http://alistair.cockburn.us/Hexagonal+architecture).

`Lockstep` cannot verify that you are using threads correctly. To ensure you're dealing with threading issues robustly you'll still need to write stress tests. What it *can* do is enable you to write isolated unit tests for your thread-aware code without having to coordinate actual threads in the context of a test. No sleeps, timeouts, deadlocked tests, test-introduced race conditions, forced rendezvous, etc. This means that you can TDD your thread-aware logic the same you would any other code.

## How is this sorcery achieved?

Go read the [source](https://github.com/avdi/lockstep/blob/master/lib/lockstep/sync_thread.rb), it's less than 100 lines of code.
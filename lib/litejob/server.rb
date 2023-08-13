# frozen_string_literal: true

require "litequeue"
require "litescheduler"

module Litejob
  # Litejob::Server is responsible for popping job payloads from the SQLite queue.
  # :nocov:
  class Server
    def initialize(queues)
      @queue = Litequeue.instance
      @scheduler = Litescheduler.instance
      @queues = queues
      # group and order queues according to their priority
      @prioritized_queues = queues.each_with_object({}) do |(name, priority, spawns), memo|
        memo[priority] ||= []
        memo[priority] << [name, spawns == "spawn"]
      end.sort_by do |priority, _|
        -priority
      end
      @running = true
      @sleep_intervals = [0.001, 0.005, 0.025, 0.125, 0.625, 1.0, 2.0]
      run!
    end

    def pop(queue)
      result = @queue.pop(queue: queue)

      return result[0] if result.length == 1
      return false if result.empty?

      result
    end

    def run!
      @scheduler.spawn do
        worker_sleep_index = 0
        while @running
          processed = 0
          @prioritized_queues.each do |priority, queues|
            queues.each do |queue, spawns|
              batched = 0
              while (batched < priority) && (payload = pop(queue))
                batched += 1
                processed += 1

                processor = Processor.new(payload)
                processor.process!

                # give other contexts a chance to run here
                @scheduler.switch
              end
            end

            if processed == 0
              sleep @sleep_intervals[worker_sleep_index]
              worker_sleep_index += 1 if worker_sleep_index < @sleep_intervals.length - 1
            else
              worker_sleep_index = 0 # reset the index
            end
          end
        end
      end
    end
  end
  # :nocov:
end

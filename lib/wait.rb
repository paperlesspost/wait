require File.expand_path("../initialize", __FILE__)

class Wait
  DEFAULT = {
    :attempts => 5,
    :timeout  => 15,
    :delay    => 1,
    :counter  => BaseCounter,
    :delayer  => RegularDelayer,
    :rescuer  => BaseRescuer,
    :tester   => TruthyTester,
    :raiser   => SignalRaiser,
    :logger   => BaseLogger
  }

  # Creates a new Wait instance.
  #
  # == Basic Options
  #
  # [:attempts]
  #   Number of times to attempt the block. Default is +5+.
  # [:timeout]
  #   Seconds until the block times out. Default is +15+.
  # [:delay]
  #   Seconds to delay in between attempts. Default is +1+.
  # [:rescue]
  #   One or an array of exceptions to rescue. Default is +nil+.
  # [:debug]
  #   If +true+, debug logging is enabled. Default is +false+.
  #
  # == Advanced Options
  #
  # [:logger]
  #   Ruby logger used. Default is Wait::BaseLogger.
  # [:counter]
  #   Strategy used to count attempts. Default is Wait::BaseCounter.
  # [:delayer]
  #   Strategy used to delay in between attempts. Default is
  #   Wait::RegularDelayer.
  # [:rescuer]
  #   Strategy used to rescue exceptions. Default is Wait::BaseRescuer.
  # [:tester]
  #   Strategy used to test the result. Default is Wait::TruthyTester.
  # [:raiser]
  #   Strategy used to raise specific exceptions. Default is
  #   Wait::SignalRaiser.
  #
  def initialize(options = {})
    # Assign defaults.
    debug      = options[:debug]    || false
    @logger    = options[:logger]   || (debug ? DebugLogger : DEFAULT[:logger]).new
    attempts   = options[:attempts] || DEFAULT[:attempts]
    @counter   = options[:counter]  || DEFAULT[:counter].new(attempts)
    @timeout   = options[:timeout]  || DEFAULT[:timeout]
    delay      = options[:delay]    || DEFAULT[:delay]
    @delayer   = options[:delayer]  || DEFAULT[:delayer].new(delay)
    exceptions = options[:rescue]
    @rescuer   = options[:rescuer]  || DEFAULT[:rescuer].new(exceptions)
    @tester    = options[:tester]   || DEFAULT[:tester].new
    @raiser    = options[:raiser]   || DEFAULT[:raiser].new

    # Assign the logger to each of the strategies.
    [@counter, @delayer, @rescuer, @tester, @raiser].each do |strategy|
      strategy.logger = @logger if strategy.respond_to?(:logger=)
    end
  end

  # == Description
  #
  # Wait#until executes a block until there's a valid (by default, truthy)
  # result. Useful for blocking script execution until:
  # * an HTTP request was successful
  # * a port has opened
  # * a process has started
  # * etc.
  #
  # == Examples
  #
  #   wait = Wait.new
  #   # => #<Wait>
  #   wait.until { Time.now.sec.even? }
  #   # [Counter] attempt 1/5
  #   # [Tester]  result: false
  #   # [Rescuer] rescued: Wait::ResultInvalid
  #   # [Raiser]  not raising: Wait::ResultInvalid
  #   # [Delayer] delaying for 1s
  #   # [Counter] attempt 2/5
  #   # [Tester]  result: true
  #   # => true
  #
  # If you wish to handle an exception by attempting the block again, pass one
  # or an array of exceptions with the +:rescue+ option.
  #
  #   wait = Wait.new(:rescue => RuntimeError)
  #   # => #<Wait>
  #   wait.until do |attempt|
  #     case attempt
  #     when 1 then nil
  #     when 2 then raise RuntimeError
  #     when 3 then "foo"
  #     end
  #   end
  #   # [Counter] attempt 1/5
  #   # [Tester]  result: nil
  #   # [Rescuer] rescued: Wait::ResultInvalid
  #   # [Raiser]  not raising: Wait::ResultInvalid
  #   # [Delayer] delaying for 1s
  #   # [Counter] attempt 2/5
  #   # [Rescuer] rescued: RuntimeError
  #   # [Raiser]  not raising: RuntimeError
  #   # [Delayer] delaying for 1s
  #   # [Counter] attempt 3/5
  #   # [Tester]  result: "foo"
  #   # => "foo"
  #
  # == Returns
  #
  # The result of the block if valid (by default, truthy).
  #
  # == Raises
  #
  # If no results are valid, the exception from the last attempt made.
  #
  def until(&block)
    # Reset the attempt counter.
    @counter.reset
    begin
      # Increment the attempt counter.
      @counter.increment
      # Wrap the given block in a timeout.
      result = Timeout.timeout(@timeout, TimeoutError) do
        # Execute the block and pass the attempt count (an +Integer+) to it.
        yield(@counter.attempt)
      end
      # Raise an exception unless the result is valid.
      @tester.valid?(result) ? result : raise(ResultInvalid)
    rescue TimeoutError, ResultInvalid, *@rescuer.exceptions => exception
      # Log the exception.
      @rescuer.log(exception)
      # Raise the exception if it ought to be.
      raise(exception) if @raiser.raise?(exception)
      # Raise the exception if this was the last attempt.
      raise(exception) if @counter.last_attempt?
      # Sleep before the next attempt.
      @delayer.sleep
      # Try the block again.
      retry
    end
  end

  # Raised when a block times out.
  class TimeoutError < Timeout::Error; end

  # Raised when a block returns an invalid result.
  class ResultInvalid < RuntimeError; end
end #Wait

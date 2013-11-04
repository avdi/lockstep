class SyncThread
  def self.interrupt(source, name, *args, &block)
    Fiber.yield(:interrupt, source, name, args, block)
  end

  def initialize
    @status = Started.new
    @fiber = Fiber.new do
      return_value = nil
      loop do
        op = Fiber.yield(:finish, return_value)
        return_value = op.call
      end
    end
    @fiber.resume
  end

  def run(options={}, &op)
    raise "Not finished!" unless @status.finished?
    execute(options) do
      @fiber.resume(op)
    end
    @status
  end

  def resume(options={})
    raise "Nothing to resume!" if @status.finished?
    execute(options) do
      @fiber.resume
    end
    @status
  end

  def finish
    return @status if @status.finished?
    resume(ignore: true)
  end

  private

  def execute(options={})
    ignores = Array(options[:ignore])
    loop do
      status, *rest = yield
      case status
      when :finish
        @status = Finished.new(rest.first)
        break
      when :interrupt
        source, name, args, block = *rest
        @status = Interrupted.new(source, name, args, block)
        break unless ignores.include?(name) || ignores.include?(true)
      else
        raise "Should never get here"
      end
    end
  end

  class Started
    def finished?; true; end
  end
  Finished = Struct.new(:return_value) do
    def finished?; true; end
    def interrupted_by?(*); false; end
  end
  Interrupted = Struct.new(:source, :name, :arguments, :block) do
    def finished?; false; end
    def interrupted_by?(source_or_message, message=nil, args=nil)
      if args
        return false unless args === arguments
      end
      if message
        return false unless message === name
        return source_or_message === source
      end
      return source_or_message === name
    end
  end
end

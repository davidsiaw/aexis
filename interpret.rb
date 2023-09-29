class Runner
  def initialize(memory, tasks, taskinfo)
    @cur_call = {}
    @memory = memory
    @stack = []
    @tasks = tasks
    @taskinfo = taskinfo
    puts "running #{@taskinfo}"
  end

  def dupl
    @stack << @stack.last
  end

  def desccall
    @cur_call = {
      inputs: [],
      outputs: [],
      name: nil
    }
  end

  def create
    id = (@memory.keys.max || 0) + 1
    @memory[id] = {
      bound: false,
      value: nil,
      refs: 0
    }
    
    @stack << id
  end

  def assign(value)
    @memory[@stack.last][:value] = value.to_i
    @memory[@stack.last][:bound] = true
  end

  def return
    memref = @stack.pop
    @cur_call[:outputs] << memref
    @memory[memref][:refs] += 1
  end

  def input
    memref = @stack.pop
    @cur_call[:inputs] << memref
    @memory[memref][:refs] += 1
  end

  def push(value)
    @stack << value
  end

  def push_func
    @cur_call[:name] = @stack.pop
    @tasks << @cur_call
  end

  def push_param(index)
    @stack << @taskinfo[:inputs][index.to_i]
  end

  def push_return(index)
    @stack << @taskinfo[:outputs][index.to_i]
  end

  def assign_top
    memref = @stack.pop
    value = @memory[memref][:value]
    assign(value)
  end
end

class CommandParser
  def initialize(cmd)
    @cmd = cmd
  end

  def toks
    @toks ||= @cmd.split(' ')
  end

  def name
    toks[0].to_sym
  end

  def params
    toks[1..-1]
  end

  def inspect
    "<cmd:#{name} #{params}>"
  end
end

class Parser
  def initialize(program)
    @program = program
  end

  def lines
    @lines ||= @program.split("\n")
  end

  def commands
    @commands ||= lines.map do |line|
      
      z = line.split(';')[0]
      z&.strip
    end.reject {|x| x&.length == 0}.compact.map{|x| CommandParser.new(x)}
  end
  
  def functions
    @functions ||= begin
      stuff = {}

      curfunc = {}
      commands.each do |command|
        if command.name == :start
          curfunc = {
            name: command.params.first,
            cmds: []
          }
        elsif command.name == :finish
          stuff[curfunc[:name]] = curfunc
        else
          curfunc[:cmds] << command
        end
      end

      stuff
    end
  end
end

class Intrinsics
  def add(a,b)
    a+b
  end

  def mul(a,b)
    a*b
  end

  def putstring(a)
    puts a
  end
end

class Interpreter
  attr_reader :tasks
  def initialize(parser)
    @parser = parser
    @memory = {}
    @tasks = []
    @curtaskinfo = nil
    @curline = 0
  end

  def intrinsics
    @intrinsics ||= Intrinsics.new
  end

  def intrinsic_key(name)
    name.sub(/^#_intrin_/, '')
  end

  def intrinsic?(name)
    intrinsics.respond_to?(intrinsic_key(name).to_sym)
  end

  def execute_intrinsic(taskinfo)
    key = intrinsic_key(taskinfo[:name])
    params = taskinfo[:inputs].map {|x| @memory[x][:value]}

    puts "running #{taskinfo}"
    # p @memory
    *result = intrinsics.send(key, *params)

    taskinfo[:outputs].each_with_index do |x, i|
      @memory[x][:value] = result[i]
      @memory[x][:bound] = true
    end
  end

  def next_available_task
    @tasks.each_with_index do |taskinfo, index|
      # check that task is calling an extant function
      if !@parser.functions.key?(taskinfo[:name])
        raise "no such function #{taskinfo[:name]}" unless intrinsic?(taskinfo[:name])
      end
      
      # check that task is ready
      if taskinfo[:inputs].any?{|input| @memory[input][:bound] == false}
        puts "skip not ready #{taskinfo}"
        next
      end

      return index
    end

    return nil
  end

  def pop_available_task
    taskindex = next_available_task
    
    return nil if taskindex.nil?
    t = tasks[taskindex]
    nt = tasks[0...taskindex] + tasks[taskindex+1..-1]

    @tasks = nt
    t
  end

  def step
    if @curtaskinfo.nil?
      return false if @tasks.length == 0

      taskinfo = pop_available_task

      if intrinsic?(taskinfo[:name])
        
        #p "intrin #{taskinfo[:name]}"
        execute_intrinsic(taskinfo)

        taskinfo[:inputs].each do |memref|
          @memory[memref][:refs] -= 1
        end

        taskinfo[:outputs].each do |memref|
          @memory[memref][:refs] -= 1
        end

        @curtaskinfo = nil
        return true
      else
        @curtaskinfo = taskinfo
        @curline = 0
        @currunner = Runner.new(@memory, @tasks, taskinfo)
      end
    end

    if @curline < @parser.functions[@curtaskinfo[:name]][:cmds].length
      #running function
      cmd = @parser.functions[@curtaskinfo[:name]][:cmds][@curline]
      @currunner.send(cmd.name, *cmd.params)
      @curline += 1

    else
      # end of function

      # dereference all vars
      @curtaskinfo[:inputs].each do |memref|
        @memory[memref][:refs] -= 1
      end

      @curtaskinfo[:outputs].each do |memref|
        @memory[memref][:refs] -= 1
      end

      @curtaskinfo = nil

      # collect no-longer-used memory
      @memory.each do |k,v|
        next if v[:refs] > 0
        puts "garbage #{k}"
        @memory.delete(k)
      end
    end

    true
  end

end

program = File.read(ARGV[0])

parser = Parser.new(program)

interpreter = Interpreter.new(parser)

# kick off
interpreter.tasks << {
  inputs: [],
  outputs: [],
  name: '#main'
}

loop do
  hasnext = interpreter.step
  # p "hasnext #{hasnext}"
  break if !hasnext
end

# p interpreter

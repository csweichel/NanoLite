module NLSL
  module Compiler

    #
    # The root scope: those variables exist by default and serve as interface to the runtime environment
    #
    ROOT_SCOPE = NLSE::Scope.new(nil,
      :nl_FragColor => :vec4,
      :nl_FragCoord => :vec3,
      :iResolution => :vec3,
      :iFragCount => :int,
      :iFragCoord => :vec3,
      :iGlobalTime => :int,
      :iFragID => :int,
      :PI => :float
    )

    def self._mkbfunc(name, types, rettype)
      arguments = types.each_with_index.inject({}) {|m, v| m[v.last] = NLSE::Value.new(:type => v.first, :value => nil, :ref => false); m }
      NLSE::Function.new(:name => name, :arguments => arguments, :type => rettype, :body => [], :builtin => true)
    end
    #
    # The root registration of built-in functions. These functions have to be supported by the runtime
    #
    BUILTIN_FUNCTIONS = {
        "vec4" => [
            _mkbfunc("vec4", [ :float, :float, :float, :float ], :vec4),
            _mkbfunc("vec4", [ :vec2, :float, :float ], :vec4),
            _mkbfunc("vec4", [ :vec3, :float ], :vec4),
        ],
        "vec3" => [
            _mkbfunc("vec3", [ :float, :float, :float ], :vec3),
            _mkbfunc("vec3", [ :vec2, :float ], :vec3)
        ],
        "vec2" => [
            _mkbfunc("vec2", [ :float, :float ], :vec2),
        ],
        "cos" => [
            _mkbfunc("cos", [ :float ], :float),
            _mkbfunc("cos", [ :int ], :float),
        ],
        "sin" => [
            _mkbfunc("sin", [ :float ], :float),
            _mkbfunc("sin", [ :int ], :float),
        ]
    }

    #######
    ## Signature convention for enabling non-strict types:
    ##   - types ordered in reverse alphabetical order
    ##   - operator comes first
    ##
    ## strictness means that an operator only makes sense when types are in a certain order (e.g., vec div scalar)
    ## associativity means that an operator can be applied to an arbitrary operand order (e.g., vec mul vec)
    ## strictness is a stronger condition that associativity (e.g., scalar div scalar is not-strict and not associative, however scalar mul scalar is also non-strict but associative )
    ##
    OPERATIONS = {
      # mul and div
      "* vec4 float" => NLSE::VectorMulScalar,
      "* vec4 int" => NLSE::VectorMulScalar,
      "/ vec4 float" => NLSE::VectorDivScalar,
      "/ vec4 int" => NLSE::VectorDivScalar,
      "* vec3 float" => NLSE::VectorMulScalar,
      "* vec3 int" => NLSE::VectorMulScalar,
      "/ vec3 float" => NLSE::VectorDivScalar,
      "/ vec3 int" => NLSE::VectorDivScalar,
      "* vec2 float" => NLSE::VectorMulScalar,
      "* vec2 int" => NLSE::VectorMulScalar,
      "/ vec2 float" => NLSE::VectorDivScalar,
      "/ vec2 int" => NLSE::VectorDivScalar,
      "* vec4 vec4" => NLSE::VectorMulVector,
      "* vec3 vec3" => NLSE::VectorMulVector,
      "* vec2 vec2" => NLSE::VectorMulVector,
      "* int float" => NLSE::ScalarMulScalar,
      "* int int" => NLSE::ScalarMulScalar,
      "* float float" => NLSE::ScalarMulScalar,
      "/ int float" => NLSE::ScalarDivScalar,
      "/ int int" => NLSE::ScalarDivScalar,
      "/ float float" => NLSE::ScalarDivScalar,

      # add and sub
      "+ vec4 vec4" => NLSE::VectorAddVector,
      "+ vec3 vec3" => NLSE::VectorAddVector,
      "+ vec2 vec2" => NLSE::VectorAddVector,
      "+ float float" => NLSE::ScalarAddScalar,
      "+ int float" => NLSE::ScalarAddScalar,
      "+ int int" => NLSE::ScalarAddScalar,
      "- vec4 vec4" => NLSE::VectorSubVector,
      "- vec3 vec3" => NLSE::VectorSubVector,
      "- vec2 vec2" => NLSE::VectorSubVector,
      "- float float" => NLSE::ScalarSubScalar,
      "- int float" => NLSE::ScalarSubScalar,
      "- int int" => NLSE::ScalarSubScalar,

      # equality
      "== int float" => NLSE::CompEqScalar,
      "== float float" => NLSE::CompEqScalar,
      "== int int" => NLSE::CompEqScalar,
      "== vec4 vec4" => NLSE::CompEqVector,
      "== vec3 vec3" => NLSE::CompEqVector,
      "== vec2 vec2" => NLSE::CompEqVector,

      # less and greater
      "< int float" => NLSE::CompLessScalar,
      "< float float" => NLSE::CompLessScalar,
      "< int int" => NLSE::CompLessScalar,
      "< vec4 vec4" => NLSE::CompLessVector,
      "< vec3 vec3" => NLSE::CompLessVector,
      "< vec2 vec2" => NLSE::CompLessVector,
      "> int float" => NLSE::CompGreaterScalar,
      "> float float" => NLSE::CompGreaterScalar,
      "> int int" => NLSE::CompGreaterScalar,
      "> vec4 vec4" => NLSE::CompGreaterVector,
      "> vec3 vec3" => NLSE::CompGreaterVector,
      "> vec2 vec2" => NLSE::CompGreaterVector,
    }

    #
    # All vector components, their result type and to which vector they're applicable
    #
    VECTOR_COMPONENTS = {
      :x => [ :float, [ :vec4, :vec3, :vec2 ] ],
      :y => [ :float, [ :vec4, :vec3, :vec2 ] ],
      :z => [ :float, [ :vec4, :vec3 ] ],
      :w => [ :float, [ :vec4 ] ],
      :xy => [ :vec2, [ :vec4, :vec3 ] ],
      :xyz => [ :vec3, [ :vec4 ] ]
    }

    #
    # Transforms an NLSL AST into NLSE code, performs type-checking and linking in the process
    #
    class Transformer

      def transform(element, scope = ROOT_SCOPE.clone, program = nil)
        throw "Scope is not a NLSE::Scope" if not scope.is_a? NLSE::Scope
        throw "Program is not a NLSE::Program" unless program.is_a?(NLSE::Program) or program.nil?

        if(element.is_a? Program)
          transform_program(element, scope, program)
        elsif element.is_a? FunctionDefinition
          transform_function(element, scope, program)
        elsif element.is_a? FunctionArgumentDefinition
          transform_argdef(element, scope, program)
        elsif element.is_a? Statement or element.is_a? Expression
          transform(element.content.first, scope, program)
        elsif element.is_a? Assignment
          transform_assignment(element, scope, program)
        elsif element.is_a? UnaryAssignment
          transform_unaryassignment(element, scope, program)
        elsif element.is_a? OperationalExpression
          transform_opexp(element, scope, program)
        elsif element.is_a? NumberLiteral
          transform_numlit(element, scope, program)
        elsif element.is_a? VariableRef
          transform_varref(element, scope, program)
        elsif element.is_a? FunctionCall
          transform_funccal(element, scope, program)
        elsif element.is_a? Comment
          NLSE::Comment.new(:value => element.value[2..-1])
        elsif element.is_a? If
          transform_if(element, scope, program)
        elsif element.is_a? While
          transform_while(element, scope, program)
        elsif element.is_a? For
          transform_for(element, scope, program)
        elsif element.is_a? Return
          transform_return(element, scope, program)
        else
          puts "Unhandled AST element: #{element.ast_module}"
        end
      end

      def transform_program(element, scope, program)
        r = NLSE::Program.new(:root_scope => scope, :functions => BUILTIN_FUNCTIONS.clone)
        element.content.each {|c| transform(c, scope, r) }
        r
      end

      def transform_function(element, scope, program)
        name = element.name
        type = element.return_type.to_sym
        nuscope = scope.branch
        args = element.arguments.inject({}) {|m,a| m[a.name] = transform(a, nuscope, program); m }
        body = element.body.statements.map {|e| transform(e, nuscope, program) }

        func = NLSE::Function.new(:name => name, :type => type, :arguments => args, :body => body, :builtin => false)
        program.register_function(func)
      end

      def transform_argdef(element, scope, program)
        name = element.name.to_sym
        type = element.type.to_sym

        scope.register_variable(name, type)
      end

      def transform_assignment(element, scope, program)
        name = element.name.to_sym
        value = transform(element.expression, scope, program)

        if element.type.nil?
          throw "Unknown variable #{name}" if not scope.include?(name)
          unless value.nil?
            throw "Type mismatch for variable \"#{name}\": #{value.type} != #{scope[name]}" if scope[name] != value.type
          end
        else
          throw "Type mismatch for variable \"#{name}\": #{element.type} != #{value.type}" if element.type.to_sym != value.type
          scope.register_variable(name, element.type.to_sym)
        end

        NLSE::VariableAssignment.new(:name => name, :value => value)
      end

      def transform_unaryassignment(element, scope, program)
        name = element.name.to_sym
        throw "Unknown variable #{name}" if not scope.include?(name)

        type = scope[name]
        throw "Unary assignments only exist for scalar types" unless type == :float or type == :int
        op    = element.operator == "++" ? NLSE::ScalarAddScalar : NLSE::ScalarSubScalar
        opsig = element.operator[-1]

        NLSE::VariableAssignment.new(:name => name, :value => op.new(
            :a => NLSE::Value.new(:type => type, :value => name, :ref => true),
            :b => NLSE::Value.new(:type => :int, :value => 1, :ref => false),
            :signature => "#{opsig} #{[type, :int].sort.reverse.join(" ")}"
        ))
      end

      def transform_opexp(element, scope, program)
        throw "OpExp with more than two factors are not yet supported" if element.factors.length > 2

        factors = element.factors.map {|e| transform(e, scope, program) }

        ## try and find with the original signature
        types = factors.map {|e| e.type.to_s }
        signature = "#{element.operator} #{types.first} #{types.last}"
        op = OPERATIONS[signature]
        if op.nil?
          ## try and and find non-strictly typed operation
          types = types.sort.reverse
          nonstrict_signature = "#{element.operator} #{types.first} #{types.last}"
          op = OPERATIONS[nonstrict_signature]

          throw "Invalid operation: #{signature}" if op.nil? or op.strict_types?
        end

        op.new(:a => factors.first, :b => factors.last, :signature => signature)
      end

      def transform_numlit(element, scope, program)
        NLSE::Value.new(:type => element.int? ? :int : :float, :value => element.value, :ref => false)
      end

      def transform_varref(element, scope, program)
        name = element.value.to_sym
        throw "Unknown variable: #{name}" if not scope.include?(name)

        type = scope[name]
        result = NLSE::Value.new(:type => type, :value => name, :ref => true)

        component = element.component
        if not component.nil?
          componentLookup = VECTOR_COMPONENTS[component.to_sym]
          throw "Invalid vector component: #{type}.#{component}" if not componentLookup.last.include?(type)

          result = NLSE::ComponentAccess.new(:type => componentLookup.first, :value => result, :component => component.to_sym)
        end

        result
      end

      def transform_funccal(element, scope, program)
        name = element.name
        funcs = program.functions[name]
        throw "Unknown function: #{name}" if funcs.nil?
        funcs = funcs.inject({}) do |m, func|
          signature = func.arguments.values.map {|a| a.type.to_s }.join(", ")
          m[signature] = func
          m
        end

        arguments = element.arguments.map {|a| transform(a, scope, program) }
        signature = arguments.map {|a| a.type.to_s }.join(", ")
        function = funcs[signature]
        throw "No function #{name}(#{signature}) found. Candidates are: #{funcs.keys.map {|s| "#{name}(#{s})" }}" if function.nil?

        NLSE::FunctionCall.new(:name => name, :arguments => arguments, :type => function.type)
      end

      def transform_if(element, scope, program)
        condition = transform(element.condition, scope, program)
        throw "Conditional must be a comparative expression: #{element.condition}" unless condition.is_a? NLSE::Condition

        then_scope = scope.branch
        then_body = element.then_body.map {|e| transform(e, then_scope, program) }
        else_body = []
        unless element.else_body.nil?
          else_scope = scope.branch
          else_body = element.else_body.map {|e| transform(e, else_scope, program) }
        end

        NLSE::If.new(:condition => condition, :then_body => then_body, :else_body => else_body)
      end

      def transform_while(element, scope, program)
        condition = transform(element.condition, scope, program)
        throw "Conditional must be a comparative expression: #{element.condition}" unless condition.is_a? NLSE::Condition

        nuscope = scope.branch
        body = element.body.content.map {|e| transform(e, nuscope, program) }
        NLSE::While.new(:condition => condition, :body => body)
      end

      def transform_for(element, scope, program)
        nuscope = scope.branch
        initialization = transform(element.initialization, nuscope, program)
        iterator = transform(element.iterator, nuscope, program)
        condition = transform(element.condition, nuscope, program)
        throw "Conditional must be a comparative expression: #{element.condition}" unless condition.is_a? NLSE::Condition

        body = element.body.content.map {|e| transform(e, nuscope, program) }

        NLSE::For.new(:init => initialization, :iterator => iterator, :condition => condition, :body => body)
      end

      def transform_return(element, scope, program)
        NLSE::Return.new(:value => transform(element.expression, scope, program))
      end

    end

  end
end

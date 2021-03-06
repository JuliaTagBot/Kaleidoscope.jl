##########
# Parser #
##########

mutable struct Parser
    l::Lexer
    current_token::Token
    Parser(str) = new(Lexer(str))
end

current_token(ps::Parser) = ps.current_token
next_token!(ps::Parser) = return (ps.current_token = gettok(ps.l))

# Operator precedence
const BinopPrecedence = Dict{Kinds.Kind, Int}()
BinopPrecedence[Kinds.EQUAL]   = 2
BinopPrecedence[Kinds.LESS]    = 10
BinopPrecedence[Kinds.GREATER] = 10
BinopPrecedence[Kinds.PLUS]    = 20
BinopPrecedence[Kinds.MINUS]   = 20
BinopPrecedence[Kinds.STAR]    = 40
BinopPrecedence[Kinds.SLASH]   = 40

function operator_precedence(ps)
    v = current_token(ps).kind
    return (v in keys(BinopPrecedence)) ? BinopPrecedence[v] : -1
end

#############
# AST Nodes #
#############

abstract type ExprAST end

struct NumberExprAST <: ExprAST
    val::Float64
end
Base.show(io::IO, expr::NumberExprAST) = print(io, expr.val)

struct VariableExprAST <: ExprAST
    name::String
end
Base.show(io::IO, expr::VariableExprAST) = print(io, expr.name)

struct BinaryExprAST <: ExprAST
    op::Kinds.Kind
    lhs::ExprAST
    rhs::ExprAST
end
Base.show(io::IO, expr::BinaryExprAST) = print(io, expr.op, "(", expr.lhs, ", ", expr.rhs, ")")

struct CallExprAST <: ExprAST
    callee::String
    args::Vector{ExprAST}
end

struct IfExprAST <: ExprAST
    cond::ExprAST
    then::ExprAST
    elsee::ExprAST
end

struct ForExprAST <: ExprAST
    varname::String
    start::ExprAST
    endd::ExprAST
    step::ExprAST
    body::ExprAST
end

struct VarExprAST <: ExprAST
    varnames::Vector{Tuple{String, ExprAST}}
end

struct BlockExprAST <: ExprAST
    exprs::Vector{ExprAST}
end

struct PrototypeAST
    name::String
    args::Vector{String}
end

struct FunctionAST
    proto::PrototypeAST
    body::ExprAST
end


#####################
# Parse Expressions #
#####################

function ParseNumberExpr(ps::Parser)::NumberExprAST
    result = NumberExprAST(Base.parse(Float64, current_token(ps).val))
    return result
end

function ParseIdentifierExpr(ps::Parser)::Union{ VariableExprAST, CallExprAST}
    idname = current_token(ps).val
    next_token!(ps) # eat the idname

    if current_token(ps).kind != Kinds.LPAR
        return VariableExprAST(idname)
    end

    next_token!(ps) # eat '('
    args = ExprAST[]
    first = true
    while true
        if current_token(ps).kind == Kinds.RPAR
            break
        end
        if !first
            if current_token(ps).kind != Kinds.COMMA
                error("Expected ')' or ',' in argument list, got $(current_token(ps))")
            end
            next_token!(ps) # eat the ','            
        end
        first = false
        push!(args, ParseExpression(ps))
    end
    next_token!(ps) # eat ')'
    return CallExprAST(idname, args)
end

function ParseIfExpr(ps)::IfExprAST
    # if
    next_token!(ps) # eat 'if'
    cond = ParseExpression(ps)

    # then
    if current_token(ps).kind != Kinds.THEN
        error("expected 'then'")
    end
    next_token!(ps) # eat 'then'
    then = ParseExpression(ps)

    # else
    if current_token(ps).kind != Kinds.ELSE
        error("expected 'else'")
    end
    next_token!(ps)
    elsee = ParseExpression(ps)

    return IfExprAST(cond, then, elsee)
end

function ParsePrototype(ps)::PrototypeAST
    if current_token(ps).kind != Kinds.IDENTIFIER
        error("Expected function name in prototype, got $(current_token(ps))")
    end

    func_name = current_token(ps).val
    tok = next_token!(ps) # eat identifier

    if tok.kind != Kinds.LPAR
        error("Expected '(' in prototype")
    end

    argnames = String[]
    while (next_token!(ps).kind == Kinds.IDENTIFIER)
        push!(argnames, current_token(ps).val)
    end

    if current_token(ps).kind != Kinds.RPAR
        error("Expected ')' in prototype, got $(current_token(ps))")
    end

    next_token!(ps)

    return PrototypeAST(func_name, argnames)
end

function ParseDefinition(ps)::FunctionAST
    next_token!(ps) # eat def
    proto = ParsePrototype(ps)
    E = ParseExpression(ps)
    return FunctionAST(proto, E)
end

function ParseParenExpr(ps::Parser)::ExprAST
    next_token!(ps) # eat '('
    V = ParseExpression(ps)
    if current_token(ps).kind != Kinds.RPAR
        error("expected ')'")
    end
    next_token!(ps) # eat ')'
    return V
end

function ParseBinOpRHS(ps, ExprPrec::Int, LHS::ExprAST)::ExprAST
    while true
        tokprec = operator_precedence(ps)
        if tokprec < ExprPrec
            return LHS
        end

        bin_op = current_token(ps)
        next_token!(ps) # eat binary token

        RHS = ParsePrimary(ps)
        nextprec = operator_precedence(ps)
        if tokprec < nextprec 
            RHS = ParseBinOpRHS(ps, tokprec + 1, RHS)
        end

        LHS = BinaryExprAST(bin_op.kind, LHS, RHS)
    end
end

function ParseForExpr(ps)::ForExprAST
    next_token!(ps) # eat 'for'

    if current_token(ps).kind != Kinds.IDENTIFIER
        error("expected identifier after for")
    end

    idname = current_token(ps).val
    next_token!(ps) # eat identifier

    if current_token(ps).kind != Kinds.EQUAL
        error("expected `=` after identifier in for expression")
    end
    next_token!(ps) # eat =

    start = ParseExpression(ps)
    if current_token(ps).kind != Kinds.COMMA
        error("expected `,` after for start value")
    end
    next_token!(ps) # eat ,

    endd = ParseExpression(ps)

    # TODO: make optional
    if current_token(ps).kind != Kinds.COMMA
        error("expected ',' after for end value")
    end
    next_token!(ps) # eat ,
    step = ParseExpression(ps)

    if current_token(ps).kind != Kinds.IN
        error("expected 'in' after for")
    end
    next_token!(ps) # eat in

    body = ParseExpression(ps)

    return ForExprAST(idname, start, endd, step, body)
end

function ParseExtern(ps)::PrototypeAST
    next_token!(ps) # eat 'extern'
    return ParsePrototype(ps)
end

function ParseVarExpr(ps)
    next_token!(ps) #eat the var
    varnames = Tuple{String, ExprAST}[]
    if current_token(ps).kind != Kinds.IDENTIFIER
        error("expected identifier after var")
    end

    while true
        name = current_token(ps).val
        next_token!(ps) # eat the identifier
        # TODO: Optional initializer
        if current_token(ps).kind != Kinds.EQUAL
            error("expected equal after var identifier")
        end
        next_token!(ps) # eat the '='
        init = ParseExpression(ps)

        push!(varnames, (name, init))

        current_token(ps).kind != Kinds.COMMA && break
        next_token!(ps) # eat the '.'
        if current_token(ps).kind != Kinds.IDENTIFIER
            error("expected identifier list after var")
        end
    end


    return VarExprAST(varnames)
end

function ParseTopLevelExpr(ps)::FunctionAST
    E = ParseExpression(ps)
    proto = PrototypeAST("__anon_expr", String[])
    return FunctionAST(proto, E)
end


@noinline function ParseExpression(ps)::ExprAST
    LHS = ParsePrimary(ps)
    return ParseBinOpRHS(ps, 0, LHS)
end

function ParseBlockExpr(ps)::BlockExprAST
    next_token!(ps) # eat the '{'
    exprs = ExprAST[]
    while true
        if current_token(ps).kind == Kinds.RBRACE
            next_token!(ps) # eat the '}'
            break
        end
        push!(exprs, ParseExpression(ps))
    end
    return BlockExprAST(exprs)
end

function ParsePrimary(ps)::ExprAST
    curtok = current_token(ps)
    if curtok.kind == Kinds.IDENTIFIER
        return ParseIdentifierExpr(ps)
    elseif curtok.kind == Kinds.NUMBER
        return ParseNumberExpr(ps)
    elseif curtok.kind == Kinds.LPAR
        return ParseParenExpr(ps)
    elseif curtok.kind == Kinds.IF
        return ParseIfExpr(ps)
    elseif curtok.kind == Kinds.FOR
        return ParseForExpr(ps)
    elseif curtok.kind == Kinds.VAR
        return ParseVarExpr(ps)
    elseif curtok.kind == Kinds.LBRACE
        return ParseBlockExpr(ps)
    else
        error("unexpected token: $curtok")
    end
end

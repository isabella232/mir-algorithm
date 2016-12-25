/**
Functions that manipulate other functions.
This module provides functions for compile time function composition. These
functions are helpful when constructing predicates for the algorithms in
$(MREF mir, algorithm) or $(MREF mir, ndslice).
$(BOOKTABLE ,
$(TR $(TH Function Name) $(TH Description)
)
    $(TR $(TD $(LREF compose))
        $(TD Join a couple of functions into one that executes the original
        functions one after the other, using one function's result for the next
        function's argument.
    ))
    $(TR $(TD $(LREF not))
        $(TD Creates a function that negates another.
    ))
    $(TR $(TD $(LREF reverseArgs), $(LREF binaryReverseArgs))
        $(TD Predicate that reverses the order of its arguments.
    ))
    $(TR $(TD $(LREF naryFun)
        $(TD Create a unary or binary function from a string. Most often
        used when defining algorithms on ranges.
    ))
)
Copyright: Andrei Alexandrescu 2008 - 2009, Ilya Yaroshenko 2016-.
License:   $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   Ilya Yaroshenko, $(HTTP erdani.org, Andrei Alexandrescu (original std.functional))
*/
/*
         Copyright Andrei Alexandrescu 2008 - 2009, Ilya Yaroshenko 2016-.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
         http://www.boost.org/LICENSE_1_0.txt)
*/
module mir.functional;

import std.meta; // AliasSeq, Reverse
import std.traits; // isCallable, Parameters


private template needOpCallAlias(alias fun)
{
    /* Determine whether or not naryFun need to alias to fun or
     * fun.opCall. Basically, fun is a function object if fun(...) compiles. We
     * want is(naryFun!fun) (resp., is(naryFun!fun)) to be true if fun is
     * any function object. There are 4 possible cases:
     *
     *  1) fun is the type of a function object with static opCall;
     *  2) fun is an instance of a function object with static opCall;
     *  3) fun is the type of a function object with non-static opCall;
     *  4) fun is an instance of a function object with non-static opCall.
     *
     * In case (1), is(naryFun!fun) should compile, but does not if naryFun
     * aliases itself to fun, because typeof(fun) is an error when fun itself
     * is a type. So it must be aliased to fun.opCall instead. All other cases
     * should be aliased to fun directly.
     */
    static if (is(typeof(fun.opCall) == function))
    {
        enum needOpCallAlias = !is(typeof(fun)) && __traits(compiles, () {
            return fun(Parameters!fun.init);
        });
    }
    else
        enum needOpCallAlias = false;
}

private template _naryAliases(size_t n)
    if (n <= 26)
{
    static if (n == 0)
        enum _naryAliases = "";
    else
    {
        enum i = n - 1;
        enum _naryAliases = _naryAliases!i ~ "alias " ~ cast(char)('a' + i) ~ " = args[" ~ i.stringof ~ "];\n";
    }
}

/**
Transforms a string representing an expression into a binary function. The
string must either use symbol names $(D a) and $(D b) as the parameters or
provide the symbols via the $(D parm1Name) and $(D parm2Name) arguments.
If $(D fun) is not a string, $(D naryFun) aliases itself away to
$(D fun).
*/

template naryFun(alias fun)
{
    static if (is(typeof(fun) : string))
    {
        /// Specialization for string lambdas
        auto ref naryFun(Args...)(auto ref Args args)
            if (args.length <= 26)
        {
            mixin(_naryAliases!(Args.length));
            return mixin(fun);
        }
    }
    else static if (needOpCallAlias!fun)
        alias naryFun = fun.opCall;
    else
        alias naryFun = fun;
}

///
@safe unittest
{
    // Strings are compiled into functions:
    alias isEven = naryFun!("(a & 1) == 0");
    assert(isEven(2) && !isEven(1));
}

///
@safe unittest
{
    alias less = naryFun!("a < b");
    assert(less(1, 2) && !less(2, 1));
    alias greater = naryFun!("a > b");
    assert(!greater("1", "2") && greater("2", "1"));
}

/// `naryFun` accepts up to 26 arguments.
@safe unittest
{
    assert(naryFun!("a * b + c")(2, 3, 4) == 10);
}

/// `naryFun` can return by reference.
unittest
{
    int a;
    assert(&naryFun!("a")(a) == &a);
}

/// `args` paramter tuple
unittest
{
    assert(naryFun!("args[0] + args[1]")(2, 3) == 5);
}

@safe unittest
{
    static int f1(int a) { return a + 1; }
    static assert(is(typeof(naryFun!(f1)(1)) == int));
    assert(naryFun!(f1)(41) == 42);
    int f2(int a) { return a + 1; }
    static assert(is(typeof(naryFun!(f2)(1)) == int));
    assert(naryFun!(f2)(41) == 42);
    assert(naryFun!("a + 1")(41) == 42);

    int num = 41;
    assert(naryFun!"a + 1"(num) == 42);

    // Issue 9906
    struct Seen
    {
        static bool opCall(int n) { return true; }
    }
    static assert(needOpCallAlias!Seen);
    static assert(is(typeof(naryFun!Seen(1))));
    assert(naryFun!Seen(1));

    Seen s;
    static assert(!needOpCallAlias!s);
    static assert(is(typeof(naryFun!s(1))));
    assert(naryFun!s(1));

    struct FuncObj
    {
        bool opCall(int n) { return true; }
    }
    FuncObj fo;
    static assert(!needOpCallAlias!fo);
    static assert(is(typeof(naryFun!fo)));
    assert(naryFun!fo(1));

    // Function object with non-static opCall can only be called with an
    // instance, not with merely the type.
    static assert(!is(typeof(naryFun!FuncObj)));
}

@safe unittest
{
    static int f1(int a, string b) { return a + 1; }
    static assert(is(typeof(naryFun!(f1)(1, "2")) == int));
    assert(naryFun!(f1)(41, "a") == 42);
    string f2(int a, string b) { return b ~ "2"; }
    static assert(is(typeof(naryFun!(f2)(1, "1")) == string));
    assert(naryFun!(f2)(1, "4") == "42");
    assert(naryFun!("a + b")(41, 1) == 42);
    //@@BUG
    //assert(naryFun!("return a + b;")(41, 1) == 42);

    // Issue 9906
    struct Seen
    {
        static bool opCall(int x, int y) { return true; }
    }
    static assert(is(typeof(naryFun!Seen)));
    assert(naryFun!Seen(1,1));

    struct FuncObj
    {
        bool opCall(int x, int y) { return true; }
    }
    FuncObj fo;
    static assert(!needOpCallAlias!fo);
    static assert(is(typeof(naryFun!fo)));
    assert(naryFun!fo(1,1));

    // Function object with non-static opCall can only be called with an
    // instance, not with merely the type.
    static assert(!is(typeof(naryFun!FuncObj)));
}

/**
   N-ary predicate that reverses the order of arguments, e.g., given
   $(D pred(a, b, c)), returns $(D pred(c, b, a)).
*/
template reverseArgs(alias fun)
{
    ///
    auto ref reverseArgs(Args...)(auto ref Args args)
        if (is(typeof(fun(Reverse!args))))
    {
        return fun(Reverse!args);
    }

}

///
@safe unittest
{
    int abc(int a, int b, int c) { return a * b + c; }
    alias cba = reverseArgs!abc;
    assert(abc(91, 17, 32) == cba(32, 17, 91));
}

@safe unittest
{
    int a(int a) { return a * 2; }
    alias _a = reverseArgs!a;
    assert(a(2) == _a(2));
}

@safe unittest
{
    int b() { return 4; }
    alias _b = reverseArgs!b;
    assert(b() == _b());
}

@safe unittest
{
    alias gt = reverseArgs!(naryFun!("a < b"));
    assert(gt(2, 1) && !gt(1, 1));
    int x = 42;
    bool xyz(int a, int b) { return a * x < b / x; }
    auto foo = &xyz;
    foo(4, 5);
    alias zyx = reverseArgs!(foo);
    assert(zyx(5, 4) == foo(4, 5));
}

/**
Negates predicate `pred`.
 */
template not(alias pred)
{
    static if (!is(typeof(pred) : string) && !needOpCallAlias!pred)
    ///
    bool not(T...)(auto ref T args)
    {
        return !pred(args);
    }
    else
        alias not = .not!(naryFun!pred);
}

///
@safe unittest
{
    import std.algorithm.searching : find;
    import std.uni : isWhite;
    string a = "   Hello, world!";
    assert(find!(not!isWhite)(a) == "Hello, world!");
}

@safe unittest
{
    assert(not!"a != 5"(5));
    assert(not!"a != b"(5, 5));

    assert(not!(() => false)());
    assert(not!(a => a != 5)(5));
    assert(not!((a, b) => a != b)(5, 5));
    assert(not!((a, b, c) => a * b * c != 125 )(5, 5, 5));
}

/**
   Composes passed-in functions `fun[0], fun[1], ...` returning a
   function `f(x)` that in turn returns
   `fun[0](fun[1](...(x)))...`. Each function can be a regular
   functions, a delegate, or a string.
*/
template compose(fun...)
{
    static if (fun.length == 2)
    {
        // starch
        alias fun0 = naryFun!(fun[0]);
        alias fun1 = naryFun!(fun[1]);

        ///
        auto ref compose(Args...)(auto ref Args args)
        {
            return fun0(fun1(args));
        }
    }
    else
    static if (fun.length == 1)
        alias compose = naryFun!(fun[0]);
    else
        alias compose = compose!(fun[0], compose!(fun[1 .. $]));
}

///
@safe unittest
{
    assert(compose!(a => a * 10, "a + b")(2, 3) == 50);
}

/// `compose` can return by reference.
unittest
{
    int a;
    assert(&compose!("a", "a")(a) == &a);
}

@safe unittest
{
    import std.algorithm.comparison : equal;
    import std.algorithm.iteration : map;
    import std.array : split;
    import std.conv : to;

    // First split a string in whitespace-separated tokens and then
    // convert each token into an integer
    assert(compose!(map!(to!(int)), split)("1 2 3").equal([1, 2, 3]));
}

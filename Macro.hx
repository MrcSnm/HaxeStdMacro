package cask.utils;


/**
 * endsWith
 */
using StringTools;

/**
 * exists
 */
using Lambda;

import haxe.macro.Expr;
import haxe.macro.Context;

class Macro
{

    ///////////////////////////// BASIC CALLABLE MACROS /////////////////////////////

    /**
     * Basic building block function.
     * It will return the value of compiler flags, those defined with 
     * `-D optimization_level=1`
     * 
     * Then, we can log it as runtime by doing
     * ```haxe
     * trace(Macro.getDefine("optimization_level")); //1
     * ```
     * @param defineName 
     */
    public static macro function getDefine(defineName : String) 
    {
        var ret = Context.definedValue(defineName);
        // trace(ret);
        return macro $v{ret};
    }

        /**
     * This is simply a macro that will swap two variables in place, or by reference.
     * ```haxe
     * var a = 500;
     * var b = 200;
     * Macro.swap(a, b);
     * 
     * trace(a); //200
     * trace(b); //500
     * ```
     * 
     * @param a 
     * @param b 
     * @return Expr
     */
    public static macro function swap(a : Expr, b : Expr) : Expr
    {
        /**
         * By returning a macro containing an expression, that means that literal block
         * will be inserted where you called this function
         */
        return macro {
            final temp = a;
            a = b;
            b = temp;
        };
    }

     /**
     * This function takes any expression and returns the variable identifier as a string.
     * 
     * ```haxe
     * 
     * var hello : String;
     * hello = Macro.nameof(hello);
     * trace(hello); //Prints "hello"
     * ```
     * 
     * @param e 
     */
    public static macro function nameof(e : Expr)
    {
        /**
         * We start match our expression 
         */
        switch(e)
        {
            /**
             * macro $i{ident} will make our expression match with its identifier.
             * We store that identifier inside the `ident` variable, which is currently
             * a string. If we wish to return that string, we need to use the `macro`
             * keyword for 
             */
            case macro $i{ident}: return macro $v{ident};
            case _: throw "Nameof must receive an identifier";
        }   
    }

    /**
     * This function is used to return a class instance from a define.
     * 
     * For instance:
     * 
     * ```haxe
     * final myInstance = Macro.newClass("CurrentTestClass", "debugging.tests");
     * ```
     * 
     * If we change the define for the CurrentTestClass, we change which instance
     * we are currently using. 
     * 
     * @param defineName 
     * @param packagePath 
     * @return Expr
     */
    macro function newClass(defineName : String, packagePath : String) : Expr
    {
        var className : String = Context.definedValue(defineName);
    
        //Construct a type path from the arguments
        var T : TypePath = {name: className, pack: packagePath.split(".")};
        //Return an instance from this type
        return macro new $T();
    }


    ///////////////////////////// PRE MIDDLE CALLABLE MACROS /////////////////////////////


    /**
     * `#if macro` gates are needed specially for the build macros.
     */
    #if macro
    /**
     * This function must be called only from withing a build macro (I think)
     * 
     * This basically does:
     * 
     * Iterate the current class to its topmost parent finding
     * for a field called `funcName`. And returns if it was found
     */
    public static function needsOverride(funcName : String) : Bool
    {
        final startClass = Context.getLocalClass().get();
        var currClass = startClass;


        //Checks the entire inheritance chain 
        while(currClass.superClass != null && 
            ((currClass = currClass.superClass.t.get()) != null))
        {
            ///Filters current class fields
            if(currClass.fields.get().exists((field) -> field.name == funcName))   
                return true;
        }
        return false;
    }
    #end


    /**
     * Here, we return the expression type stringified. This is useful for instance:
     * 
     * ```haxe
     * var myInt : Int = 500;
     * 
     * trace("myInt type is " + Macro.getTypeName(myInt) + " and its value is " + myInt);//Prints "myInt type is Int and its value is 500"
     * ```
     * This can be extremely useful for compile time type information.
     * 
     * @param e 
     */
    public static macro function getTypeName(e : Expr)
    {
        switch (haxe.macro.Context.typeof(e))
        {
            //That means return the literal value of t.toString
            case TAbstract(t, params): //TAbstract means we will match abstract. Such as Int, Float, etc
                return macro $v{t.toString()};
            case TInst(t, params): //TInst means we will match classes. Such as any kind of user defined classes
                return macro $v{t.toString()};
            default: return macro $v{"null"};
        }
    }


    /**
     * Use this function as means to get the type symbol. This may be
     * useful for getting Class<SomeType> symbols·
     * @param e 
     */
    public static macro function getType(e : Expr)
    {
        switch (haxe.macro.Context.typeof(e))
        {
            //That means, return the identifier called t.toString
            case TAbstract(t, params):
                return macro $i{t.toString()};
            //$p means that we will construct the type path constructed from the typename string.
            //It is also possible to use $i{}, but then it won't match symbols that are defined on another packages
            case TInst(t, params): 
                return macro $p{t.toString().split('.')};
            default: return macro null;
        }
    }


    ///////////////////////////// BASIC BUILD MACROS /////////////////////////////


    #if macro
    /**
     * This function is a build macro. What it does is basically:
     * 
     * 1. Find all function that starts with `get_`
     * 2. Creates a virtual field without the `get_` prefix, which will only have a getter.
     * @return Array<Field>
     */
    public static macro function build_generateGetter() : Array<Field>
    {
        var fields : Array<Field> = Context.getBuildFields();
        for(i in 0...fields.length)
        {
            if(fields[i].name.substr(0, 4) == "get_")
            {
                ///Check which kind of field is that
                var ret = switch(fields[i].kind)
                {
                    ///If it is a function, we get its return type
                    case FFun(f): f.ret;
                    case _: null;
                }
                
                var field : Field = {
                    name: fields[i].name.substr(4), //We create a field without "get_"
                    access: fields[i].access, //With the same level of access as the get_ func
                    pos : Context.currentPos(), //At the current position
                    kind: FProp("get", "never", ret) //Using as virtual (get, never) with the function ret type
                };

                //Then we push that field to the class
                fields.push(field);
            }
        }
        return fields;
    }
    #end

    /**
     * This function will load a json from the given path at compile time, it will
     * parse it either for being to error check.
     * 
     * 
     * @param filePath 
     * @return Dynamic
     */
    macro function loadJSON(filePath : String) : Dynamic
    {
        //Check file existence
        if(sys.FileSystem.exists(filePath))
        {
            //Use IO API to read the file
            var data = sys.io.File.getContent(filePath);
        
            var json;
            //Parse it
            try{json = Json.parse(data);}
            catch (error : String)
            {
                //If an error occurred in parsing, we then get the error position
                var position = Std.parseInt(error.split("position").pop());
                var pos = haxe.macro.Context.makePosition({
                    min:position,
                    max:position+1,
                    file:filePath
                });
                //And send a new hygienized error for understanding what really happened
                haxe.macro.Context.error(filePath + " is not valid Json." + error, pos);
            }
            //Then we return the literal value of the `json` variable
            return macro $v{json};
        }
        else //If the file doesn't exists then we throw an error saying that
            haxe.macro.Context.error(filePath+" does not exist", haxe.macro.Context.currentPos());

        //This return statement should be unreachable
        return macro null;
    
    }

    
}


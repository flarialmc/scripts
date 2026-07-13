name = "Calculator"
description = "Arithmetic Calculator in Minecraft itself use .calc for more info"
author = "Streoids"
aliases = {"calc", "calchelp"}

function execute(args)
    if #args==0 then
        print("§eCalc is a simple calculator that runs in Minecraft, by §6S§6t§6r§6e§6o§6i§6d§6s")
        print("§fIt can perform arithmetic functions such as:")
        print("§o§bAddition [ + ]")
        print("§o§bSubtraction [ - ]")
        print("§o§bMultiplication [ * ]")
        print("§o§bDivision [ / ]")
        print("§o§bExponentiation [ ^ ]")
        print("§eExamples:")
        print("§b.calc 5+2")
        print("§b.calc (5+5)*2")
        print("§b.calc 16/2")
        print("§b.calc 6-3")
        print("§b.calc 6^2")
        return
    end
    local expression=table.concat(args, " ")
    if expression:match("[+%-/%*%^][+%-/%*%^]") then
        return print("§4calc: Invalid operator")
    end
    if expression:match("%a") then
        return print("§4calc: Invalid calculation")
    end
    local func=load("return "..expression)
    if not func then return print("§4calc: Invalid input") end
    local success, result=pcall(func)
    if not success then return print("§4calc: Invalid calculation") end
    if result==math.huge or result==-math.huge then
        return print("§4calc: Can't divide by 0.")
    end
    print("§acalc: "..(math.floor(result)==result and math.floor(result) or result))
end

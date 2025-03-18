name="Calculator"
description="Arithmetic Calculator in Minecraft itself"
author="Streoids"
function onLoad()
    registerCommand("calc", function(args)
        if #args == 0 then return print("§4calc: No calculation detected. use .calchelp for help")
        end
        local expression=table.concat(args," ")
        if expression:match("[+%-/%*%^][+%-/%*%^]")then
            return print("§4calc: Invalid operator")
        end
        if expression:match("%a")then
            return print("§4calc: Invalid calculation")
        end
        local func=load("return"..expression)
        if not func then return print("§4calc: Invalid input")
        end
        local success, result=pcall(func)
        if not success then return print("§4calc: Invalid calculation")
        end
        if result==math.huge or result==-math.huge then 
            return print("§4calc: can't divide by 0. Consider getting an education")
        end
        print("§acalc: "..(result==math.floor(result) and math.floor(result) or result))
    end)
    registerCommand("calchelp", function()
        print("§ecalc is a simple calculator that runs in Minecraft, by §6S§6t§6r§6e§6o§6i§6d§6s")
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
        print("§k§2!.§a:§2'§r §4Flarial on top! §k§2!.§a:§2'")
    end)
end

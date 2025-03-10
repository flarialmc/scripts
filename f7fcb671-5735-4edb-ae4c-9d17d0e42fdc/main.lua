function onEnable()
end

function onDisable()
end

onEvent(EventType.onPacketReceiveEvent, function(packet, id)
    if id == MinecraftPacketIds.SetTitle then -- check if its a set title packet
        text = SetTitle.getPacket(packet).text -- sets the value to copy
        io.popen("echo " .. text .. " | clip"):close() -- copy to clipboard
    end
end)

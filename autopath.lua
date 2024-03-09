require('common')
local chat = require('chat')
local settings = require('settings')

addon.name = 'autopath'
addon.author = 'gnubeardo'
addon.version = '1.0'
addon.desc = 'Records and plays back paths'
addon.link = 'https://github.com/ErikDahlinghaus/autopath'

local default_settings = T{
    record_interval = 0.3
}

local a_path = T{
    name = "mypath",
    nodes = T{
        T{ zone = 204, x = 1, y = 1, z = 1 },
        T{ zone = 204, x = 2, y = 2, z = 2 }
    }
}

local autopath = T{
    settings = settings.load(default_settings),
    recording = false,
    playing = false,
    paths = T{
        a_path
    }
}

local function print_paths()
    for _key, path in pairs(autopath.paths) do
        print(chat.header('autopath') .. chat.message(path.name))
    end
end
















local function print_table(tbl, indent)
    indent = indent or 0

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            print((" "):rep(indent) .. key .. ":")
            print_table(value, indent + 2)
        else
            print((" "):rep(indent) .. key .. ": " .. tostring(value))
        end
    end
end

function printMethods(obj)
    local metatable = getmetatable(obj)

    if metatable and type(metatable) == "table" then
        print("Methods:")
        for key, value in pairs(metatable) do
            if type(value) == "function" then
                print(key)
            end
        end
    else
        print("No metatable found or metatable is not a table.")
    end
end

function copyAndModify(original, keyToModify, newValue)
    local copy = {}

    -- Copy each key-value pair
    for key, value in pairs(original) do
        copy[key] = value
    end

    -- Modify the specified key in the copy
    copy[keyToModify] = newValue

    return copy
end
















local function get_position()
    local player = GetPlayerEntity()

    if (player == nil) then
        print(chat.header('autopath') .. chat.message("Player Entity Nil"))
        return
    end

    local x = player.Movement.LocalPosition.X
    local y = player.Movement.LocalPosition.Y
    local z = player.Movement.LocalPosition.Z
    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)

    return T{ zone = zone, x = x, y = y, z = z }
end

local function move_to_position(target_position)
    local autofollow = AshitaCore:GetMemoryManager():GetAutoFollow()
    local at_position = false
    local iterations = 100

    while (not at_position and iterations > 0 and autopath.playing) do
        local current_position = get_position()
        local d_x = current_position.x - target_position.x
        local d_y = current_position.y - target_position.y

        autofollow:SetFollowDeltaX(-d_x);
        autofollow:SetFollowDeltaY(-d_y);

        local auto_run = autofollow:GetIsAutoRunning()
        if ( auto_run ~= 1 ) then
            autofollow:SetIsAutoRunning(1)
        end

        local delta_dist = math.sqrt(math.pow(d_x, 2) + math.pow(d_y, 2))
        if ( delta_dist <= 0.5 ) then
            at_position = true
        end
        iterations = iterations - 1

        coroutine.sleep(0.1)
    end

    autofollow:SetIsAutoRunning(0)
end





local function record_path(path_name)
    autopath.recording = true
    while( autopath.recording ) do
        local position = get_position()
        print_table(position)

        coroutine.sleep(autopath.settings.record_interval)
    end
end








settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        todbot.settings = s
    end
    settings.save()
end)

ashita.events.register('unload', 'unload_cb', function()
    settings.save()
end)

ashita.events.register('command', 'command_cb', function(e)
    local command_args = e.command:lower():args()
    if table.contains({'/autopath'}, command_args[1]) then
        if table.contains({'record'}, command_args[2]) then
            local path_name = command_args[3]
            if path_name then
                print(chat.header('autopath') .. chat.message(string.format("Recording %s", path_name)))
                record_path(path_name)
            else
                print(chat.header('autopath') .. chat.message("Name required: /autopath record <name>"))
            end
        elseif table.contains({'play'}, command_args[2]) then
            local path_name = command_args[3]
            if path_name then
                print(chat.header('autopath') .. chat.message(string.format("Playing %s", path_name)))
            else
                print(chat.header('autopath') .. chat.message("Name required: /autopath play <name>"))
            end
        elseif table.contains({'stop'}, command_args[2]) then
            autopath.recording = false
            autopath.playing = false
            print(chat.header('autopath') .. chat.message("Stopped"))
        elseif table.contains({'list'}, command_args[2]) then
            print_paths()
        elseif table.contains({'debug'}, command_args[2]) then
            local position = get_position()
            if not position then
                return
            end
            print_table(position)

            local new_position = copyAndModify(position, 'x', position.x - 0)
            new_position = copyAndModify(new_position, 'y', position.y + 20)
            autopath.playing = true
            move_to_position(new_position)
        else
            print(chat.header('autopath') .. chat.message("/autopath record <name>"))
            print(chat.header('autopath') .. chat.message("/autopath play <name>"))
            print(chat.header('autopath') .. chat.message("/autopath stop"))
            print(chat.header('autopath') .. chat.message("/autopath list"))
        end
    end
    return false
end)
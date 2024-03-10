require('common')
local chat = require('chat')
local settings = require('settings')

addon.name = 'autopath'
addon.author = 'gnubeardo'
addon.version = '1.0'
addon.desc = 'Records and plays back paths'
addon.link = 'https://github.com/ErikDahlinghaus/autopath'

local default_settings = T{
    record_interval = 0.3,
    max_distance_to_path = 20,
    paths = T{}
}

local autopath = T{
    settings = settings.load(default_settings),
    recording = false,
    playing = false
}

local function tables_are_equal(table1, table2)
    if type(table1) ~= "table" or type(table2) ~= "table" then
        return false
    end

    for key, value in pairs(table1) do
        if type(value) == "table" then
            if not tables_are_equal(value, table2[key]) then
                return false
            end
        elseif table2[key] ~= value then
            return false
        end
    end

    for key, value in pairs(table2) do
        if type(value) == "table" then
            if not tables_are_equal(value, table1[key]) then
                return false
            end
        elseif table1[key] ~= value then
            return false
        end
    end

    return true
end

function deduplicate_nodes(path_nodes)
    local seen_nodes = {}
    local deduplicated_nodes = {}

    for _, node in ipairs(path_nodes) do
        local is_duplicate = false

        for _, seen_node in ipairs(seen_nodes) do
            if tables_are_equal(node, seen_node) then
                is_duplicate = true
                break
            end
        end

        if not is_duplicate then
            table.insert(seen_nodes, node)
            table.insert(deduplicated_nodes, node)
        end
    end

    return deduplicated_nodes
end

local function save_path(new_path)
    for i, path in ipairs(autopath.settings.paths) do
        if path['name'] == new_path.name then
            autopath.settings.paths[i] = new_path
            return
        end
    end

    table.insert(autopath.settings.paths, new_path)
    settings.save()
end

local function delete_path_by_name(path_name)
    for i, path in ipairs(autopath.settings.paths) do
        if path['name'] == path_name then
            table.remove(autopath.settings.paths, i)
            print(chat.header('autopath') .. chat.message(string.format("Deleted path %s", path_name)))
            settings.save()
            return
        end
    end
    
    print(chat.header('autopath') .. chat.message(string.format("No path to delete named %s", path_name)))
end

local function get_position()
    local player = GetPlayerEntity()

    if (player == nil) then
        print(chat.header('autopath') .. chat.message("Error while getting position -- Player Entity nil"))
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

    while ( not at_position and autopath.playing ) do
        local current_position = get_position()
        if ( not current_position ) then
            print(chat.header('autopath') .. chat.message("Could not get current position"))
            autopath.playing = false
            autofollow:SetIsAutoRunning(0)
            return
        end

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
        if ( iterations == 0 ) then
            print(chat.header('autopath') .. chat.message("Could not navigate to position in 10 seconds"))
            autopath.playing = false
            autofollow:SetIsAutoRunning(0)
            return
        end

        coroutine.sleep(0.1)
    end

    autofollow:SetIsAutoRunning(0)
    return true
end

local function path_by_name(path_name)
    for _, path in ipairs(autopath.settings.paths) do
        if path['name'] == path_name then
            return path
        end
    end
    return
end

local function find_closest_node(nodes)
    local current_position = get_position()

    local closest_node = T{
        index = nil,
        distance = math.huge
    }
    
    for i, node_position in ipairs(nodes) do
        local distance = math.sqrt(
            (node_position.x - current_position.x)^2 +
            (node_position.y - current_position.y)^2
        )

        if distance < closest_node.distance then
            closest_node.distance = distance
            closest_node.index = i
        end
    end

    return closest_node
end

local function play_path(path_name)
    local path = path_by_name(path_name)
    if ( not path ) then
        print(chat.header('autopath') .. chat.message(string.format("Could not find path by name %s", path_name)))
        return
    end

    local current_position = get_position()
    if ( path.nodes[1].zone ~= current_position.zone ) then
        print(chat.header('autopath') .. chat.message("You are not in the correct zone to start this path"))
        return
    end

    local closest_node = find_closest_node(path.nodes)
    if ( closest_node.distance >= autopath.settings.max_distance_to_path ) then
        print(chat.header('autopath') .. chat.message("Too far from path to start"))
        return
    end

    autopath.playing = true
    for i = closest_node.index, #path.nodes do

        local node = path.nodes[i]
        if ( not autopath.playing ) then
            break
        end

        local success = move_to_position(node)
        if ( not success ) then
            print(chat.header('autopath') .. chat.message("Unable to path to node, stopping playback"))
            autopath.playing = false
            return
        end
    end

    print(chat.header('autopath') .. chat.message("Destination reached, stopping playback"))
    autopath.playing = false
    return
end

local function record_path(path_name)
    autopath.recording = true
    nodes = T{}

    while( autopath.recording ) do
        local position = get_position()
        if ( not position ) then
            print(chat.header('autopath') .. chat.message("Could not get current position, stopping recording"))
            autopath.recording = false
            return
        end

        table.insert(nodes, position)

        coroutine.sleep(autopath.settings.record_interval)
    end

    local path = T{
        name = path_name,
        nodes = deduplicate_nodes(nodes)
    }

    save_path(path)
    return true
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
                play_path(path_name)
            else
                print(chat.header('autopath') .. chat.message("Name required: /autopath play <name>"))
            end
        elseif table.contains({'stop'}, command_args[2]) then
            autopath.recording = false
            autopath.playing = false
            print(chat.header('autopath') .. chat.message("Stopped"))
        elseif table.contains({'list'}, command_args[2]) then
            if ( #autopath.settings.paths == 0 ) then
                print(chat.header('autopath') .. chat.message("No recorded paths"))
            else
                for _, path in pairs(autopath.settings.paths) do
                    print(chat.header('autopath') .. chat.message(path.name))
                end
            end
        elseif table.contains({'delete'}, command_args[2]) then
            local path_name = command_args[3]
            if path_name then
                delete_path_by_name(path_name)
            else
                print(chat.header('autopath') .. chat.message("Name required: /autopath delete <name>"))
            end
        elseif command_args[2] then
            local path_name = command_args[2]
            print(chat.header('autopath') .. chat.message(string.format("Playing %s", path_name)))
            play_path(path_name)
        else
            print(chat.header('autopath') .. chat.message("/autopath record <name> - Begins recording path"))
            print(chat.header('autopath') .. chat.message("/autopath stop - Stop recording or playing path"))
            print(chat.header('autopath') .. chat.message("/autopath play <name> - Play a path"))
            print(chat.header('autopath') .. chat.message("/autopath delete <name> - Delete a path"))
            print(chat.header('autopath') .. chat.message("/autopath list - List paths"))

        end
    end
    return false
end)
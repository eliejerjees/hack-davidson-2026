-- Cursor for DAWs (REAPER ReaScript)
-- End-to-end flow:
-- 1) prompt for natural language
-- 2) send command + context to Python bridge
-- 3) show preview
-- 4) apply only after explicit confirmation

math.randomseed(os.time())

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function show_error(message)
    reaper.ShowMessageBox(message or "Unknown error.", "Cursor for DAWs", 0)
end

local function shell_quote(value)
    local escaped = tostring(value)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("%$", "\\$")
        :gsub("`", "\\`")
    return '"' .. escaped .. '"'
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

local function write_file(path, contents)
    local file = io.open(path, "wb")
    if not file then
        return false
    end
    file:write(contents)
    file:close()
    return true
end

local function get_script_dir()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("^(.*)[/\\]") or "."
end

local function make_temp_json_path(kind)
    local tmp = os.tmpname()
    if not tmp or tmp == "" then
        local base = reaper.GetResourcePath()
        local now_ms = math.floor(reaper.time_precise() * 1000)
        local suffix = math.random(100000, 999999)
        return string.format("%s/cursor_%s_%d_%d.json", base, kind, now_ms, suffix)
    end
    return tmp .. "_" .. kind .. ".json"
end

local function get_python_executable(script_dir)
    local venv_python3 = script_dir .. "/.venv/bin/python3"
    if file_exists(venv_python3) then
        return venv_python3
    end

    local venv_python = script_dir .. "/.venv/bin/python"
    if file_exists(venv_python) then
        return venv_python
    end

    return "python3"
end

local function json_encode_string(value)
    local escaped = value
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
    return '"' .. escaped .. '"'
end

local function is_array(tbl)
    local count = 0
    for key, _ in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
    end
    for i = 1, count do
        if tbl[i] == nil then
            return false
        end
    end
    return true
end

local function json_encode(value)
    local value_type = type(value)
    if value_type == "nil" then
        return "null"
    end
    if value_type == "boolean" then
        return value and "true" or "false"
    end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    end
    if value_type == "string" then
        return json_encode_string(value)
    end
    if value_type ~= "table" then
        error("Unsupported value type for JSON encoding: " .. value_type)
    end

    if is_array(value) then
        local parts = {}
        for i = 1, #value do
            parts[#parts + 1] = json_encode(value[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local parts = {}
    for key, item in pairs(value) do
        parts[#parts + 1] = json_encode_string(tostring(key)) .. ":" .. json_encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function json_decode(text)
    local index = 1

    local function skip_ws()
        while true do
            local c = text:sub(index, index)
            if c == " " or c == "\n" or c == "\r" or c == "\t" then
                index = index + 1
            else
                break
            end
        end
    end

    local parse_value

    local function parse_string()
        index = index + 1
        local chars = {}
        while true do
            local c = text:sub(index, index)
            if c == "" then
                error("Unterminated string")
            end
            if c == '"' then
                index = index + 1
                return table.concat(chars)
            end
            if c == "\\" then
                local esc = text:sub(index + 1, index + 1)
                if esc == '"' or esc == "\\" or esc == "/" then
                    chars[#chars + 1] = esc
                    index = index + 2
                elseif esc == "b" then
                    chars[#chars + 1] = "\b"
                    index = index + 2
                elseif esc == "f" then
                    chars[#chars + 1] = "\f"
                    index = index + 2
                elseif esc == "n" then
                    chars[#chars + 1] = "\n"
                    index = index + 2
                elseif esc == "r" then
                    chars[#chars + 1] = "\r"
                    index = index + 2
                elseif esc == "t" then
                    chars[#chars + 1] = "\t"
                    index = index + 2
                elseif esc == "u" then
                    local hex = text:sub(index + 2, index + 5)
                    local code = tonumber(hex, 16) or 63
                    if utf8 and utf8.char then
                        chars[#chars + 1] = utf8.char(code)
                    else
                        chars[#chars + 1] = "?"
                    end
                    index = index + 6
                else
                    error("Invalid escape sequence")
                end
            else
                chars[#chars + 1] = c
                index = index + 1
            end
        end
    end

    local function parse_number()
        local start = index
        local c = text:sub(index, index)
        if c == "-" then
            index = index + 1
        end

        c = text:sub(index, index)
        if c == "0" then
            index = index + 1
        else
            while text:sub(index, index):match("%d") do
                index = index + 1
            end
        end

        if text:sub(index, index) == "." then
            index = index + 1
            while text:sub(index, index):match("%d") do
                index = index + 1
            end
        end

        c = text:sub(index, index)
        if c == "e" or c == "E" then
            index = index + 1
            c = text:sub(index, index)
            if c == "+" or c == "-" then
                index = index + 1
            end
            while text:sub(index, index):match("%d") do
                index = index + 1
            end
        end

        local value = tonumber(text:sub(start, index - 1))
        if value == nil then
            error("Invalid number")
        end
        return value
    end

    local function parse_array()
        index = index + 1
        local result = {}
        skip_ws()
        if text:sub(index, index) == "]" then
            index = index + 1
            return result
        end
        while true do
            result[#result + 1] = parse_value()
            skip_ws()
            local c = text:sub(index, index)
            if c == "," then
                index = index + 1
                skip_ws()
            elseif c == "]" then
                index = index + 1
                return result
            else
                error("Expected ',' or ']' in array")
            end
        end
    end

    local function parse_object()
        index = index + 1
        local result = {}
        skip_ws()
        if text:sub(index, index) == "}" then
            index = index + 1
            return result
        end
        while true do
            if text:sub(index, index) ~= '"' then
                error("Expected string key")
            end
            local key = parse_string()
            skip_ws()
            if text:sub(index, index) ~= ":" then
                error("Expected ':' after key")
            end
            index = index + 1
            skip_ws()
            result[key] = parse_value()
            skip_ws()
            local c = text:sub(index, index)
            if c == "," then
                index = index + 1
                skip_ws()
            elseif c == "}" then
                index = index + 1
                return result
            else
                error("Expected ',' or '}' in object")
            end
        end
    end

    parse_value = function()
        skip_ws()
        local c = text:sub(index, index)
        if c == '"' then
            return parse_string()
        end
        if c == "{" then
            return parse_object()
        end
        if c == "[" then
            return parse_array()
        end
        if c == "-" or c:match("%d") then
            return parse_number()
        end
        if text:sub(index, index + 3) == "true" then
            index = index + 4
            return true
        end
        if text:sub(index, index + 4) == "false" then
            index = index + 5
            return false
        end
        if text:sub(index, index + 3) == "null" then
            index = index + 4
            return nil
        end
        error("Invalid JSON value")
    end

    local value = parse_value()
    skip_ws()
    if index <= #text then
        error("Trailing characters after JSON value")
    end
    return value
end

local function for_each_selected_track(fn)
    local track_count = reaper.CountSelectedTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            fn(track)
        end
    end
end

local function for_each_selected_item(fn)
    local item_count = reaper.CountSelectedMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            fn(item)
        end
    end
end

local function get_selected_items()
    local items = {}
    local item_count = reaper.CountSelectedMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            items[#items + 1] = item
        end
    end
    return items
end

local function get_time_selection()
    local start_pos, end_pos = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_pos and end_pos and end_pos > start_pos then
        return start_pos, end_pos
    end
    return nil, nil
end

function fade_out(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then
        return
    end
    for_each_selected_item(function(item)
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local fade_seconds = math.min(seconds, length)
        reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_seconds)
    end)
end

function fade_in(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then
        return
    end
    for_each_selected_item(function(item)
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local fade_seconds = math.min(seconds, length)
        reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_seconds)
    end)
end

function volume(db_change)
    db_change = tonumber(db_change) or 0
    local gain = 10 ^ (db_change / 20)
    for_each_selected_track(function(track)
        local current_volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
        if current_volume <= 0 then
            current_volume = 0.000001
        end
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", current_volume * gain)
    end)
end

function volume_percent_delta(percent_delta)
    percent_delta = tonumber(percent_delta) or 0
    local multiplier = 1 + (percent_delta / 100.0)
    if multiplier < 0 then
        multiplier = 0
    end

    for_each_selected_track(function(track)
        local current_volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
        if current_volume < 0 then
            current_volume = 0
        end
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", current_volume * multiplier)
    end)
end

function volume_percent_set(percent)
    percent = tonumber(percent) or 100
    if percent < 0 then
        percent = 0
    end
    local gain = percent / 100.0

    for_each_selected_track(function(track)
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", gain)
    end)
end

function pan(pan_value)
    pan_value = clamp(tonumber(pan_value) or 0, -1, 1)
    for_each_selected_track(function(track)
        reaper.SetMediaTrackInfo_Value(track, "D_PAN", pan_value)
    end)
end

function add_compressor()
    for_each_selected_track(function(track)
        reaper.TrackFX_AddByName(track, "ReaComp (Cockos)", false, -1)
    end)
end

function add_eq()
    for_each_selected_track(function(track)
        reaper.TrackFX_AddByName(track, "ReaEQ (Cockos)", false, -1)
    end)
end

function add_reverb()
    for_each_selected_track(function(track)
        local fx_index = reaper.TrackFX_AddByName(track, "ReaVerbate (Cockos)", false, -1)
        if fx_index < 0 then
            reaper.TrackFX_AddByName(track, "ReaVerb (Cockos)", false, -1)
        end
    end)
end

function mute(state)
    local value = state and 1 or 0
    for_each_selected_track(function(track)
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", value)
    end)
end

function solo(state)
    local value = state and 1 or 0
    for_each_selected_track(function(track)
        reaper.SetMediaTrackInfo_Value(track, "I_SOLO", value)
    end)
end

function crossfade(seconds)
    local items = get_selected_items()
    if #items ~= 2 then
        return
    end

    local first_item = items[1]
    local second_item = items[2]

    local first_pos = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
    local second_pos = reaper.GetMediaItemInfo_Value(second_item, "D_POSITION")
    if second_pos < first_pos then
        first_item, second_item = second_item, first_item
    end

    local first_start = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
    local first_length = reaper.GetMediaItemInfo_Value(first_item, "D_LENGTH")
    local first_end = first_start + first_length
    local second_length = reaper.GetMediaItemInfo_Value(second_item, "D_LENGTH")

    local overlap = tonumber(seconds) or 0
    overlap = clamp(overlap, 0, math.min(first_length, second_length))
    if overlap <= 0 then
        return
    end

    reaper.SetMediaItemInfo_Value(second_item, "D_POSITION", first_end - overlap)
    reaper.SetMediaItemInfo_Value(first_item, "D_FADEOUTLEN", overlap)
    reaper.SetMediaItemInfo_Value(second_item, "D_FADEINLEN", overlap)
end

function cut_middle(seconds)
    local remove_seconds = tonumber(seconds) or 0
    if remove_seconds <= 0 then
        return
    end

    local items = get_selected_items()
    for i = 1, #items do
        local item = items[i]
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_len > 0.002 then
            local cut_amount = math.min(remove_seconds, item_len - 0.001)
            if cut_amount > 0 then
                local midpoint = item_pos + (item_len / 2)
                local cut_start = midpoint - (cut_amount / 2)
                local cut_end = midpoint + (cut_amount / 2)

                local right_of_first_split = reaper.SplitMediaItem(item, cut_start)
                if right_of_first_split then
                    local right_of_second_split = reaper.SplitMediaItem(right_of_first_split, cut_end)
                    if right_of_second_split then
                        local middle_track = reaper.GetMediaItem_Track(right_of_first_split)
                        if middle_track then
                            reaper.DeleteTrackMediaItem(middle_track, right_of_first_split)
                        end
                        local new_right_pos = reaper.GetMediaItemInfo_Value(right_of_second_split, "D_POSITION") - cut_amount
                        reaper.SetMediaItemInfo_Value(right_of_second_split, "D_POSITION", new_right_pos)
                    end
                end
            end
        end
    end
end

function split_at_cursor()
    local cursor = reaper.GetCursorPosition()
    local items = get_selected_items()
    if #items > 0 then
        for i = 1, #items do
            reaper.SplitMediaItem(items[i], cursor)
        end
        return
    end

    local ts_start, ts_end = get_time_selection()
    if not ts_start or not ts_end then
        return
    end

    local track_count = reaper.CountTracks(0)
    for track_index = 0, track_count - 1 do
        local track = reaper.GetTrack(0, track_index)
        if track then
            local item_count = reaper.CountTrackMediaItems(track)
            for item_index = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(track, item_index)
                if item then
                    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local item_end = item_start + item_len
                    local intersects_time_selection = item_end > ts_start and item_start < ts_end
                    local cursor_inside_item = cursor > item_start and cursor < item_end
                    if intersects_time_selection and cursor_inside_item then
                        reaper.SplitMediaItem(item, cursor)
                    end
                end
            end
        end
    end
end

function duplicate(count)
    local duplicate_count = tonumber(count) or 0
    duplicate_count = math.floor(duplicate_count)
    if duplicate_count < 1 then
        return
    end

    local has_items = reaper.CountSelectedMediaItems(0) > 0
    local has_tracks = reaper.CountSelectedTracks(0) > 0

    if has_items then
        for _ = 1, duplicate_count do
            reaper.Main_OnCommand(40057, 0)
        end
        return
    end

    if has_tracks then
        for _ = 1, duplicate_count do
            reaper.Main_OnCommand(40062, 0)
        end
    end
end

function trim_to_time_selection()
    local ts_start, ts_end = get_time_selection()
    if not ts_start or not ts_end then
        return
    end

    local items = get_selected_items()
    for i = 1, #items do
        local item = items[i]
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_start + item_len

        local trimmed_start = math.max(item_start, ts_start)
        local trimmed_end = math.min(item_end, ts_end)

        if trimmed_end <= trimmed_start then
            local track = reaper.GetMediaItem_Track(item)
            if track then
                reaper.DeleteTrackMediaItem(track, item)
            end
        else
            local active_take = reaper.GetActiveTake(item)
            if active_take and trimmed_start > item_start then
                local start_offs = reaper.GetMediaItemTakeInfo_Value(active_take, "D_STARTOFFS")
                reaper.SetMediaItemTakeInfo_Value(active_take, "D_STARTOFFS", start_offs + (trimmed_start - item_start))
            end

            reaper.SetMediaItemInfo_Value(item, "D_POSITION", trimmed_start)
            reaper.SetMediaItemInfo_Value(item, "D_LENGTH", trimmed_end - trimmed_start)
        end
    end
end

local function collect_context()
    local ctx = {
        selected_items = {},
        selected_tracks = {},
        time_selection = nil,
        cursor = reaper.GetCursorPosition(),
    }

    local track_count = reaper.CountSelectedTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            local _, name = reaper.GetTrackName(track, "")
            ctx.selected_tracks[#ctx.selected_tracks + 1] = {
                name = name,
                index = i + 1,
            }
        end
    end

    local item_count = reaper.CountSelectedMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            ctx.selected_items[#ctx.selected_items + 1] = {
                start = start_pos,
                ["end"] = start_pos + length,
                length = length,
            }
        end
    end

    local time_start, time_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if time_end and time_start and time_end > time_start then
        ctx.time_selection = {
            start = time_start,
            ["end"] = time_end,
        }
    end

    return ctx
end

local function dispatch_tool_call(tool_call)
    local name = tool_call.name
    local args = tool_call.args or {}

    if name == "fade_out" then
        fade_out(args.seconds)
    elseif name == "fade_in" then
        fade_in(args.seconds)
    elseif name == "set_volume_delta" then
        if args.db ~= nil then
            volume(args.db)
        elseif args.percent ~= nil then
            volume_percent_delta(args.percent)
        end
    elseif name == "set_volume_set" then
        volume_percent_set(args.percent)
    elseif name == "set_pan" then
        local pan_value = tonumber(args.pan) or 0
        pan(pan_value / 100.0)
    elseif name == "add_fx" then
        if args.type == "compressor" then
            add_compressor()
        elseif args.type == "eq" then
            add_eq()
        elseif args.type == "reverb" then
            add_reverb()
        end
    elseif name == "mute" then
        mute(true)
    elseif name == "unmute" then
        mute(false)
    elseif name == "solo" then
        solo(true)
    elseif name == "unsolo" then
        solo(false)
    elseif name == "crossfade" then
        crossfade(args.seconds)
    elseif name == "cut_middle" then
        cut_middle(args.seconds)
    elseif name == "split_at_cursor" then
        split_at_cursor()
    elseif name == "duplicate" then
        duplicate(args.count)
    elseif name == "trim_to_time_selection" then
        trim_to_time_selection()
    end
end

local function run_bridge(command, ctx)
    local script_dir = get_script_dir()
    local bridge_path = script_dir .. "/reaper_py/bridge.py"
    local input_path = make_temp_json_path("input")
    local output_path = make_temp_json_path("output")
    local python_exec = get_python_executable(script_dir)
    local payload = {cmd = command, ctx = ctx}

    if not write_file(input_path, json_encode(payload)) then
        return nil, "Failed to write bridge input file."
    end

    local exec_candidates = {python_exec}
    if python_exec ~= "python3" then
        exec_candidates[#exec_candidates + 1] = "python3"
    end

    local attempts = {}
    for i = 1, #exec_candidates do
        local executable = exec_candidates[i]
        local bridge_cmd = string.format(
            "%s %s %s %s",
            shell_quote(executable),
            shell_quote(bridge_path),
            shell_quote(input_path),
            shell_quote(output_path)
        )
        attempts[#attempts + 1] = {label = executable .. " direct", cmd = bridge_cmd}
        attempts[#attempts + 1] = {label = executable .. " zsh", cmd = string.format("/bin/zsh -lc %s", shell_quote(bridge_cmd))}
    end
    local diagnostics = {}

    for i = 1, #attempts do
        local attempt = attempts[i]
        local exit_code, exec_output = reaper.ExecProcess(attempt.cmd, 120000)
        local output_text = read_file(output_path)

        if output_text and output_text ~= "" then
            os.remove(input_path)
            os.remove(output_path)

            local ok, parsed_or_error = pcall(json_decode, output_text)
            if not ok then
                return nil, "Failed to parse bridge output JSON."
            end
            return parsed_or_error, nil
        end

        if exec_output and exec_output ~= "" then
            local ok_stdout, parsed_stdout = pcall(json_decode, exec_output)
            if ok_stdout and type(parsed_stdout) == "table" and parsed_stdout.ok ~= nil then
                os.remove(input_path)
                os.remove(output_path)
                return parsed_stdout, nil
            end
        end

        local diag = string.format("[%s] exit=%s", attempt.label, tostring(exit_code))
        if exec_output and exec_output ~= "" then
            diag = diag .. "\n" .. exec_output
        end
        diagnostics[#diagnostics + 1] = diag
    end

    os.remove(input_path)
    os.remove(output_path)

    local details = table.concat(diagnostics, "\n---\n")
    if details ~= "" then
        details = "\nDiagnostics:\n" .. details
    end
    return nil, "Python bridge returned no output." .. details
end

local function main()
    local ok, command_csv = reaper.GetUserInputs("Cursor for DAWs", 1, "Command:,extrawidth=300", "")
    if not ok then
        return
    end

    local command = (command_csv or ""):match("^%s*(.-)%s*$")
    if command == "" then
        return
    end

    local ctx = collect_context()
    local response, bridge_error = run_bridge(command, ctx)
    if bridge_error then
        show_error(bridge_error)
        return
    end

    if not response.ok then
        show_error(response.error or "Bridge returned an error.")
        return
    end

    if response.needs_clarification then
        reaper.ShowMessageBox(response.clarification_question or "Clarification needed.", "Cursor for DAWs", 0)
        return
    end

    local preview_text = response.preview or "No preview generated."
    local apply = reaper.ShowMessageBox(preview_text .. "\n\nApply? (y/n)", "Cursor Preview", 4)
    if apply ~= 6 then
        return
    end

    local tool_calls = response.tool_calls or {}
    if #tool_calls == 0 then
        show_error("No tool calls to apply.")
        return
    end

    reaper.Undo_BeginBlock()
    for i = 1, #tool_calls do
        dispatch_tool_call(tool_calls[i])
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Cursor AI Edit", -1)
end

main()

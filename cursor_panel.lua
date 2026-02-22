-- Cursor for DAWs - ReaImGui docked panel UI
-- Primary in-REAPER UX (chat + command + speech)

if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox(
        "ReaImGui is required.\nInstall it via ReaPack: Extensions -> ReaPack -> Browse Packages -> ReaImGui.",
        "Cursor for DAWs",
        0
    )
    return
end

math.randomseed(os.time())

local WINDOW_TITLE = "Cursor for DAWs"
local EXTSTATE_SECTION = "CursorForDAWsPanel"
local EXTSTATE_DOCK_HINT_KEY = "dock_hint_dismissed"
local EXTSTATE_AUTODOCK_KEY = "autodock_attempted"
local FFMPEG = "/opt/homebrew/bin/ffmpeg"
local AFPLAY = "/usr/bin/afplay"

local function get_extstate(key, default_value)
    if reaper.GetExtState then
        local value = reaper.GetExtState(EXTSTATE_SECTION, key)
        if value and value ~= "" then
            return value
        end
    end
    return default_value
end

local function set_extstate(key, value)
    if reaper.SetExtState then
        reaper.SetExtState(EXTSTATE_SECTION, key, tostring(value), true)
    end
end

local context_flags = 0
if reaper.ImGui_ConfigFlags_DockingEnable then
    local ok_flag, docking_flag = pcall(reaper.ImGui_ConfigFlags_DockingEnable)
    if ok_flag and type(docking_flag) == "number" then
        context_flags = context_flags + docking_flag
    end
end

local imgui_ctx = nil
if context_flags ~= 0 then
    local ok_ctx, ctx = pcall(reaper.ImGui_CreateContext, WINDOW_TITLE, context_flags)
    if ok_ctx and ctx then
        imgui_ctx = ctx
    end
end
if not imgui_ctx then
    imgui_ctx = reaper.ImGui_CreateContext(WINDOW_TITLE)
end

local history = {}
local command_input = ""
local pending_question = nil
local pending_intent = nil
local last_user_intent = nil
local forced_target = nil
local clarification_attempted = false
local last_error = nil
local status_line = "Ready"
local is_planning = false
local scroll_history_to_bottom = false
local show_dock_hint = get_extstate(EXTSTATE_DOCK_HINT_KEY, "0") ~= "1"
local autodock_pending = get_extstate(EXTSTATE_AUTODOCK_KEY, "0") ~= "1"
local speech_status_line = "Idle"
local speech_error = nil
local speak_after_run = false
local speech_last_response = ""
local speech_voice_override = ""
local speech_audio_device_override = ""
local stt_duration_options = {3, 5, 8}
local stt_duration_index = 2
local ffmpeg_checked = false
local ffmpeg_available = false
local ffmpeg_error = nil
local speech_recording_active = false
local speech_recording_started_at = 0
local speech_recording_duration = 0
local speech_recording_audio_path = nil
local speech_recording_pid_path = nil
local speech_recording_log_path = nil
local macos_audio_input_index_cache = nil


local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function format_time(seconds)
    local s = tonumber(seconds) or 0
    local m = math.floor(s / 60)
    local rem = s - (m * 60)
    return string.format("%02d:%06.3f", m, rem)
end

local function normalize_text(text)
    local value = tostring(text or "")
    value = value:gsub("selected items", "selected clips")
    value = value:gsub("selected item", "selected clip")
    value = value:gsub("item%(s%)", "clip(s)")
    value = value:gsub("items", "clips")
    value = value:gsub("Item", "Clip")
    return value
end

local function trim(text)
    return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function get_os_details()
    local os_name = ""
    if reaper.GetOS then
        os_name = tostring(reaper.GetOS() or "")
    end
    local lower = string.lower(os_name)
    return os_name, lower
end

local function is_windows_os(os_lower)
    return os_lower:find("win", 1, true) ~= nil
end

local function is_macos_os(os_lower)
    return os_lower:find("osx", 1, true) ~= nil
        or os_lower:find("mac", 1, true) ~= nil
        or os_lower:find("darwin", 1, true) ~= nil
end

local function append_history(role, text, always)
    history[#history + 1] = {role = role, text = normalize_text(text)}
    scroll_history_to_bottom = true
end

local function set_status(text)
    local value = tostring(text or "Ready")
    value = value:gsub("[\r\n]+", " ")
    value = value:gsub("%s+", " ")
    value = trim(value)
    if value == "" then
        value = "Ready"
    end
    if #value > 220 then
        value = value:sub(1, 217) .. "..."
    end
    status_line = value
end

local function checkbox_compat(label, current_value)
    local ok, changed_or_value, maybe_value = pcall(reaper.ImGui_Checkbox, imgui_ctx, label, current_value)
    if not ok then
        return false, current_value
    end
    if type(maybe_value) == "boolean" then
        return changed_or_value, maybe_value
    end
    if type(changed_or_value) == "boolean" then
        return changed_or_value ~= current_value, changed_or_value
    end
    return false, current_value
end

local function clear_state()
    history = {}
    command_input = ""
    pending_question = nil
    pending_intent = nil
    last_user_intent = nil
    forced_target = nil
    clarification_attempted = false
    speech_last_response = ""
    speech_audio_device_override = ""
    last_error = nil
    speech_error = nil
    speech_status_line = "Idle"
    speech_recording_active = false
    speech_recording_started_at = 0
    speech_recording_duration = 0
    speech_recording_audio_path = nil
    speech_recording_pid_path = nil
    speech_recording_log_path = nil
    macos_audio_input_index_cache = nil
    scroll_history_to_bottom = false
    set_status("Ready")
end

local function begin_child_compat(id, width, height, bordered)
    local border_flag = 0
    if bordered then
        if reaper.ImGui_ChildFlags_Border then
            border_flag = reaper.ImGui_ChildFlags_Border()
        elseif reaper.ImGui_WindowFlags_AlwaysUseWindowPadding then
            -- Older ReaImGui builds use window flags only.
            border_flag = reaper.ImGui_WindowFlags_AlwaysUseWindowPadding()
        end
    end

    -- Newer API: BeginChild(ctx, id, w, h, child_flags, window_flags)
    local ok_new, visible_new = pcall(reaper.ImGui_BeginChild, imgui_ctx, id, width, height, border_flag, 0)
    if ok_new then
        return true, visible_new
    end

    -- Older API: BeginChild(ctx, id, w, h, flags)
    local ok_old_flags, visible_old_flags = pcall(reaper.ImGui_BeginChild, imgui_ctx, id, width, height, border_flag)
    if ok_old_flags then
        return true, visible_old_flags
    end

    -- Legacy API: BeginChild(ctx, id, w, h, border_bool)
    local ok_legacy, visible_legacy = pcall(reaper.ImGui_BeginChild, imgui_ctx, id, width, height, bordered and true or false)
    if ok_legacy then
        return true, visible_legacy
    end

    -- Final fallback with minimal args.
    local ok_min, visible_min = pcall(reaper.ImGui_BeginChild, imgui_ctx, id, width, height)
    if ok_min then
        return true, visible_min
    end

    return false, false
end

local function shell_quote(value)
    local escaped = tostring(value)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("%$", "\\$")
        :gsub("`", "\\`")
    return '"' .. escaped .. '"'
end

local function shell_single_quote(value)
    local escaped = tostring(value):gsub("'", [['"'"']])
    return "'" .. escaped .. "'"
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

local function file_size(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local size = file:seek("end")
    file:close()
    return size
end

local function read_pid_from_file(path)
    local raw = read_file(path)
    if not raw then
        return nil
    end
    local pid_text = tostring(raw):match("(%d+)")
    if not pid_text then
        return nil
    end
    return tonumber(pid_text)
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

local function make_temp_path(kind, extension)
    local ext = extension or "json"
    if ext:sub(1, 1) == "." then
        ext = ext:sub(2)
    end
    local tmp = os.tmpname()
    if not tmp or tmp == "" then
        local base = reaper.GetResourcePath()
        local now_ms = math.floor(reaper.time_precise() * 1000)
        local suffix = math.random(100000, 999999)
        return string.format("%s/cursor_panel_%s_%d_%d.%s", base, kind, now_ms, suffix, ext)
    end
    return tmp .. "_" .. kind .. "." .. ext
end

local function make_temp_json_path(kind)
    return make_temp_path(kind, "json")
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
    for_each_selected_item(function(item)
        items[#items + 1] = item
    end)
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

    local time_start, time_end = get_time_selection()
    if time_start and time_end then
        ctx.time_selection = {start = time_start, ["end"] = time_end}
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

local function run_bridge_payload(payload)
    local script_dir = get_script_dir()
    local bridge_path = script_dir .. "/reaper_py/bridge.py"
    local input_path = make_temp_json_path("input")
    local output_path = make_temp_json_path("output")
    local python_exec = get_python_executable(script_dir)

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

local function clear_pending_plan_state()
    pending_question = nil
    forced_target = nil
    clarification_attempted = false
end

local function run_shell_command(command, timeout_ms, use_zsh_fallback)
    local attempts = {command}
    local _, os_lower = get_os_details()
    local allow_fallback = use_zsh_fallback
    if allow_fallback == nil then
        allow_fallback = true
    end
    if allow_fallback and not is_windows_os(os_lower) then
        attempts[#attempts + 1] = string.format("/bin/zsh -lc %s", shell_quote(command))
    end

    local diagnostics = {}
    for i = 1, #attempts do
        local cmd = attempts[i]
        local exit_code, output = reaper.ExecProcess(cmd, timeout_ms or 15000)
        if tonumber(exit_code) == 0 then
            return true, output or ""
        end
        diagnostics[#diagnostics + 1] = string.format("[attempt %d exit=%s] %s", i, tostring(exit_code), output or "")
    end
    return false, nil, table.concat(diagnostics, "\n")
end

local function run_python_script(script_rel_path, args, timeout_ms)
    local script_dir = get_script_dir()
    local script_path = script_dir .. "/" .. script_rel_path
    if not file_exists(script_path) then
        return false, nil, "Missing script: " .. script_path
    end

    local python_exec = get_python_executable(script_dir)
    local exec_candidates = {python_exec}
    if python_exec ~= "python3" then
        exec_candidates[#exec_candidates + 1] = "python3"
    end

    local diagnostics = {}
    for i = 1, #exec_candidates do
        local executable = exec_candidates[i]
        local parts = {
            shell_quote(executable),
            shell_quote(script_path),
        }
        for j = 1, #args do
            parts[#parts + 1] = shell_quote(tostring(args[j]))
        end
        local command = table.concat(parts, " ")
        local ok, output, err = run_shell_command(command, timeout_ms or 30000, false)
        if ok then
            return true, output, nil
        end
        diagnostics[#diagnostics + 1] = string.format("[%s] %s", executable, err or "unknown error")
    end
    return false, nil, table.concat(diagnostics, "\n---\n")
end

local function detect_ffmpeg()
    if ffmpeg_checked then
        return ffmpeg_available
    end

    ffmpeg_checked = true

    -- First: check file exists
    if file_exists(FFMPEG) then
        ffmpeg_available = true
        return true
    end

    -- Fallback: try executing
    local ok = run_shell_command(shell_quote(FFMPEG) .. " -version", 6000, false)
    ffmpeg_available = ok and true or false

    if not ffmpeg_available then
        ffmpeg_error = "Recording requires ffmpeg at: " .. FFMPEG
    end

    return ffmpeg_available
end

local function detect_macos_audio_input_index()
    local _, os_lower = get_os_details()
    if not is_macos_os(os_lower) then
        return 0
    end

    local override_text = trim(speech_audio_device_override or "")
    local override_number = tonumber(override_text)
    if override_number then
        return math.max(0, math.floor(override_number))
    end

    local env_override = tonumber(os.getenv("CURSOR_AVFOUNDATION_AUDIO_INDEX") or "")
    if env_override then
        return math.max(0, math.floor(env_override))
    end

    if macos_audio_input_index_cache ~= nil then
        return macos_audio_input_index_cache
    end

    local list_cmd = string.format(
        "%s -hide_banner -f avfoundation -list_devices true -i %s",
        shell_quote(FFMPEG),
        shell_quote("")
    )
    local ok, output, err = run_shell_command(list_cmd, 8000, false)
    local text = tostring(output or "")
    if text == "" and err then
        text = tostring(err)
    end

    local in_audio_section = false
    local first_index = nil
    local preferred_index = nil
    for line in text:gmatch("[^\r\n]+") do
        local lower = string.lower(line)
        if lower:find("audio devices", 1, true) then
            in_audio_section = true
        elseif in_audio_section and lower:find("video devices", 1, true) then
            in_audio_section = false
        end

        if in_audio_section then
            local idx_text, name = line:match("%[(%d+)%]%s*(.+)")
            if idx_text then
                local idx = tonumber(idx_text)
                if idx then
                    if first_index == nil then
                        first_index = idx
                    end
                    local name_lower = string.lower(name or "")
                    if preferred_index == nil and (
                        name_lower:find("microphone", 1, true)
                        or name_lower:find("mic", 1, true)
                        or name_lower:find("input", 1, true)
                        or name_lower:find("headset", 1, true)
                        or name_lower:find("airpods", 1, true)
                    ) then
                        preferred_index = idx
                    end
                end
            end
        end
    end

    if preferred_index ~= nil then
        macos_audio_input_index_cache = preferred_index
    elseif first_index ~= nil then
        macos_audio_input_index_cache = first_index
    else
        if not ok and ffmpeg_error == nil then
            ffmpeg_error = "Could not list macOS audio inputs; defaulting to index 0."
        end
        macos_audio_input_index_cache = 0
    end
    return macos_audio_input_index_cache
end

local function process_is_alive(pid)
    if not pid then
        return false
    end
    local _, os_lower = get_os_details()
    if is_windows_os(os_lower) then
        return false
    end
    local ok = run_shell_command(string.format("kill -0 %d", pid), 1000, false)
    return ok and true or false
end

local function record_voice_command(seconds)
    if not detect_ffmpeg() then
        return nil, ffmpeg_error or ("Recording requires ffmpeg at: " .. FFMPEG)
    end

    local output_path = make_temp_path("voice_cmd", "wav")
    local duration = tonumber(seconds) or 5
    local os_name, os_lower = get_os_details()

    local record_cmd
    if is_macos_os(os_lower) then
        local audio_index = detect_macos_audio_input_index()
        record_cmd = string.format(
            "%s -hide_banner -loglevel error -y -f avfoundation -i %s -t %.2f -ac 1 -ar 16000 %s",
            shell_quote(FFMPEG),
            shell_quote(":" .. tostring(audio_index)),
            duration,
            shell_quote(output_path)
        )
    elseif is_windows_os(os_lower) then
        record_cmd = string.format(
            "%s -hide_banner -loglevel error -y -f dshow -i %s -t %.2f -ac 1 -ar 16000 %s",
            shell_quote(FFMPEG),
            shell_quote("audio=default"),
            duration,
            shell_quote(output_path)
        )
    else
        record_cmd = string.format(
            "%s -hide_banner -loglevel error -y -f pulse -i %s -t %.2f -ac 1 -ar 16000 %s",
            shell_quote(FFMPEG),
            shell_quote("default"),
            duration,
            shell_quote(output_path)
        )
    end

    local ok, _, err = run_shell_command(record_cmd, 25000, false)
    if not ok or not file_exists(output_path) then
        if file_exists(output_path) then
            os.remove(output_path)
        end
        local message = "Failed to record voice command."
        if is_macos_os(os_lower) then
            message = message .. "\nOn macOS, check: Settings -> Privacy & Security -> Microphone -> REAPER."
        end
        if os_name ~= "" then
            message = message .. "\nDetected OS: " .. os_name
        end
        if err and err ~= "" then
            message = message .. "\n" .. err
        end
        return nil, message
    end
    return output_path, nil
end

local function run_stt(audio_path)
    local output_json_path = make_temp_json_path("speech_stt_output")
    local ok, _, err = run_python_script("reaper_py/speech_bridge.py", {"stt", audio_path, output_json_path}, 45000)
    local output_text = read_file(output_json_path)
    os.remove(output_json_path)
    os.remove(audio_path)

    if not ok and (not output_text or output_text == "") then
        return nil, "STT bridge failed." .. ((err and err ~= "") and ("\n" .. err) or "")
    end
    if not output_text or output_text == "" then
        return nil, "STT bridge returned no output."
    end

    local parsed_ok, parsed_or_err = pcall(json_decode, output_text)
    if not parsed_ok or type(parsed_or_err) ~= "table" then
        return nil, "Invalid STT bridge JSON."
    end
    if not parsed_or_err.ok then
        return nil, tostring(parsed_or_err.error or "STT failed.")
    end
    local text = trim(parsed_or_err.text or "")
    if text == "" then
        return nil, "Transcription was empty."
    end
    return text, nil
end

local function run_tts(text, voice_override)
    local spoken_text = trim(text)
    if spoken_text == "" then
        return nil, "Nothing to speak."
    end

    local input_text_path = make_temp_path("speech_tts_input", "txt")
    local output_mp3_path = make_temp_path("speech_tts_output", "mp3")
    if not write_file(input_text_path, spoken_text) then
        return nil, "Failed to write TTS input file."
    end

    local args = {"tts", input_text_path, output_mp3_path}
    if voice_override and trim(voice_override) ~= "" then
        args[#args + 1] = trim(voice_override)
    end

    local ok, _, err = run_python_script("reaper_py/speech_bridge.py", args, 30000)
    os.remove(input_text_path)
    if not ok or not file_exists(output_mp3_path) then
        if file_exists(output_mp3_path) then
            os.remove(output_mp3_path)
        end
        local detail = trim(tostring(err or "")):match("^[^\r\n]+")
        if detail and detail ~= "" then
            return nil, "TTS synthesis failed. " .. detail
        end
        return nil, "TTS synthesis failed."
    end
    return output_mp3_path, nil
end

local function play_tts_file(audio_path)
    local _, os_lower = get_os_details()
    local ok, _, err

    if is_macos_os(os_lower) then
        local player = file_exists(AFPLAY) and AFPLAY or "afplay"
        local payload = string.format("%s %s > /dev/null 2>&1 &", shell_quote(player), shell_quote(audio_path))
        local launch_cmd = string.format("/bin/zsh -lc %s", shell_single_quote(payload))
        local exit_code, output = reaper.ExecProcess(launch_cmd, 5000)
        ok = tonumber(exit_code) == 0
        err = ok and nil or tostring(output or "")
    elseif is_windows_os(os_lower) then
        ok, _, err = run_shell_command(string.format("cmd /c start \"\" %s", shell_quote(audio_path)), 20000)
    else
        ok, _, err = run_shell_command(string.format("xdg-open %s", shell_quote(audio_path)), 20000)
    end

    if not ok then
        local brief = trim(tostring(err or "")):match("^[^\r\n]+")
        if brief and brief ~= "" then
            return "Saved speech to: " .. audio_path .. " (auto-play failed: " .. brief .. ")"
        end
        return "Saved speech to: " .. audio_path .. " (auto-play failed)."
    end
    return nil
end

local function question_is_target_choice(question)
    local lower = string.lower(tostring(question or ""))
    local has_clip = lower:find("clip", 1, true) ~= nil
    local has_track = lower:find("track", 1, true) ~= nil
    return has_clip and has_track
end

local function infer_intent_from_command(command)
    local lower = string.lower(trim(command))
    local intent = {
        kind = nil,
        phrase = nil,
        expects_number = false,
        forced_target = nil,
    }

    if lower == "" then
        return intent
    end

    if lower:find("volume", 1, true) or lower:find("turn it down", 1, true) or lower:find("turn down", 1, true) then
        intent.kind = "volume"
        intent.expects_number = true
        if lower:find("lower", 1, true) or lower:find("down", 1, true) or lower:find("decrease", 1, true) then
            intent.phrase = "lower volume"
        elseif lower:find("raise", 1, true) or lower:find("increase", 1, true) or lower:find("up", 1, true) then
            intent.phrase = "raise volume"
        else
            intent.phrase = "adjust volume"
        end
        return intent
    end

    if lower:find("fade out", 1, true) then
        intent.kind = "fade_out"
        intent.phrase = "fade out"
        intent.expects_number = true
        return intent
    end
    if lower:find("fade in", 1, true) then
        intent.kind = "fade_in"
        intent.phrase = "fade in"
        intent.expects_number = true
        return intent
    end
    if lower:find("crossfade", 1, true) then
        intent.kind = "crossfade"
        intent.phrase = "crossfade"
        intent.expects_number = true
        return intent
    end
    if lower:find("middle", 1, true) and lower:find("cut", 1, true) then
        intent.kind = "cut_middle"
        intent.phrase = "cut middle"
        intent.expects_number = true
        return intent
    end
    if lower:find("duplicate", 1, true) then
        intent.kind = "duplicate"
        intent.phrase = "duplicate"
        intent.expects_number = true
        return intent
    end
    if lower:find("pan", 1, true) then
        intent.kind = "pan"
        intent.phrase = "set pan"
        intent.expects_number = true
        return intent
    end

    intent.phrase = trim(command)
    return intent
end

local function infer_intent_from_tool_calls(command, tool_calls, target)
    local fallback = infer_intent_from_command(command)
    local first = tool_calls and tool_calls[1] or nil
    if type(first) ~= "table" then
        fallback.forced_target = target
        return fallback
    end

    local name = first.name
    local args = type(first.args) == "table" and first.args or {}
    local intent = {
        kind = nil,
        phrase = nil,
        expects_number = false,
        forced_target = target,
    }

    if name == "set_volume_delta" then
        intent.kind = "volume"
        intent.expects_number = true
        local amount = tonumber(args.db or args.percent or 0) or 0
        intent.phrase = amount < 0 and "lower volume" or "raise volume"
    elseif name == "set_volume_set" then
        intent.kind = "volume"
        intent.phrase = "set volume to"
        intent.expects_number = true
    elseif name == "fade_out" then
        intent.kind = "fade_out"
        intent.phrase = "fade out"
        intent.expects_number = true
    elseif name == "fade_in" then
        intent.kind = "fade_in"
        intent.phrase = "fade in"
        intent.expects_number = true
    elseif name == "crossfade" then
        intent.kind = "crossfade"
        intent.phrase = "crossfade"
        intent.expects_number = true
    elseif name == "cut_middle" then
        intent.kind = "cut_middle"
        intent.phrase = "cut middle"
        intent.expects_number = true
    elseif name == "duplicate" then
        intent.kind = "duplicate"
        intent.phrase = "duplicate"
        intent.expects_number = true
    elseif name == "set_pan" then
        intent.kind = "pan"
        intent.phrase = "set pan"
        intent.expects_number = true
    else
        intent = fallback
        intent.forced_target = target
        return intent
    end

    return intent
end

local function is_parameter_only_input(input_text, allow_plain_number)
    local raw = trim(input_text)
    if raw == "" then
        return false
    end

    local lower = string.lower(raw)
    local compact = lower:gsub("%s+", "")

    if compact:match("^[%+%-]?%d+%.?%d*db$") then
        return true
    end
    if compact:match("^[%+%-]?%d+%.?%d*%%$") then
        return true
    end
    if lower:find("percent", 1, true) and lower:match("[%+%-]?%d+%.?%d*") then
        return true
    end

    local time_units = {"milliseconds", "msec", "ms", "seconds", "sec", "s"}
    for i = 1, #time_units do
        local suffix = time_units[i]
        if #compact > #suffix and compact:sub(-#suffix) == suffix then
            local number_text = compact:sub(1, #compact - #suffix)
            if tonumber(number_text) ~= nil then
                return true
            end
        end
    end

    if allow_plain_number and compact:match("^[%+%-]?%d+%.?%d*$") then
        return true
    end

    return false
end

local function build_followup_command(intent, user_value)
    local value = trim(user_value)
    local kind = intent and intent.kind or nil
    local phrase = intent and intent.phrase or "adjust"

    if kind == "volume" then
        if phrase == "set volume to" then
            return "set volume to " .. value
        end
        return phrase .. " by " .. value
    end
    if kind == "fade_out" then
        return "fade this out by " .. value
    end
    if kind == "fade_in" then
        return "fade this in by " .. value
    end
    if kind == "crossfade" then
        return "crossfade these by " .. value
    end
    if kind == "cut_middle" then
        return "cut " .. value .. " from the middle"
    end
    if kind == "duplicate" then
        return "duplicate this " .. value .. " times"
    end
    if kind == "pan" then
        return "set pan to " .. value
    end
    return phrase .. " " .. value
end

local function first_preview_action(preview_text)
    local text = tostring(preview_text or "")
    for line in text:gmatch("[^\n]+") do
        local bullet = line:match("^%-%s*(.+)$")
        if bullet then
            return bullet
        end
    end
    local compact = trim(text)
    if compact == "" then
        return "Applied edits"
    end
    return compact
end

local function build_conversation_hint()
    local hint = {}
    if last_user_intent and last_user_intent.phrase then
        hint.last_intent = tostring(last_user_intent.phrase)
    end
    if pending_intent and pending_intent.original_cmd then
        hint.pending_intent = tostring(pending_intent.original_cmd)
    end
    if next(hint) == nil then
        return nil
    end
    return hint
end

local function execute_tool_calls_now(tool_calls)
    if not tool_calls or #tool_calls == 0 then
        return 0
    end

    reaper.Undo_BeginBlock()
    for i = 1, #tool_calls do
        dispatch_tool_call(tool_calls[i])
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Cursor for DAWs: AI edit", -1)
    return #tool_calls
end

local function run_command_flow(command, target, from_followup)
    local normalized_command = trim(command)
    if normalized_command == "" then
        return
    end

    is_planning = true
    set_status("Planning...")
    last_error = nil

    local payload = {
        cmd = normalized_command,
        ctx = collect_context(),
    }
    if target then
        payload.forced_target = target
        payload.clarification_answer = target
    end
    local hint = build_conversation_hint()
    if hint then
        payload.conversation_hint = hint
    end

    local response, bridge_error = run_bridge_payload(payload)
    is_planning = false

    if bridge_error then
        last_error = normalize_text(bridge_error)
        append_history("system", "Error: " .. last_error, true)
        set_status("Error: " .. last_error)
        clear_pending_plan_state()
        pending_intent = nil
        return
    end

    if not response.ok then
        last_error = normalize_text(response.error or "Bridge returned an error.")
        append_history("system", "Error: " .. last_error, true)
        set_status("Error: " .. last_error)
        clear_pending_plan_state()
        pending_intent = nil
        return
    end

    if response.needs_clarification then
        if target or from_followup then
            last_error = "Could not resolve command after one follow-up. Try one complete command."
            append_history("system", "Error: " .. last_error, true)
            set_status("Error: " .. last_error)
            clear_pending_plan_state()
            pending_intent = nil
            return
        end

        pending_question = normalize_text(response.clarification_question or "Please clarify your command.")
        forced_target = nil
        clarification_attempted = false

        local seed_intent = infer_intent_from_command(normalized_command)
        pending_intent = {
            original_cmd = normalized_command,
            forced_target = nil,
            kind = seed_intent.kind,
            phrase = seed_intent.phrase,
            expects_number = seed_intent.expects_number,
            attempted = false,
        }

        append_history("system", pending_question, true)
        set_status("Waiting for clarification")
        return
    end

    local tool_calls = response.tool_calls or {}
    local preview_text = normalize_text(response.preview or "No preview generated.")
    pending_question = nil
    pending_intent = nil
    forced_target = nil
    clarification_attempted = false
    last_error = nil
    speech_error = nil
    last_user_intent = infer_intent_from_tool_calls(normalized_command, tool_calls, target)

    local ran_count = execute_tool_calls_now(tool_calls)
    local ran_summary = first_preview_action(preview_text)
    local ran_message = "Ran: " .. ran_summary
    append_history("system", ran_message, true)
    speech_last_response = ran_message
    set_status(string.format("Ran %d action(s)", ran_count))
end

local function maybe_speak_feedback(text)
    local spoken_text = trim(text)
    if not speak_after_run or spoken_text == "" then
        return
    end

    local mp3_path, tts_error = run_tts(spoken_text, speech_voice_override)
    if not mp3_path then
        speech_error = normalize_text(tts_error or "TTS failed.")
        speech_status_line = "Error: " .. speech_error
        append_history("system", "Error: " .. speech_error, true)
        set_status("Error: " .. speech_error)
        return
    end

    local play_error = play_tts_file(mp3_path)
    if play_error then
        speech_error = normalize_text(play_error)
        speech_status_line = "Saved speech file (auto-play failed)."
        return
    end
    speech_status_line = "Spoken feedback played."
end

local function submit_user_command(raw_input, source_tag)
    local user_input = trim(raw_input)
    if user_input == "" then
        last_error = "Enter a command first."
        set_status("Error: Enter a command first.")
        return
    end

    local user_role = source_tag == "voice" and "user_voice" or "user"
    append_history(user_role, user_input, true)

    local allow_plain_number = pending_intent ~= nil or (last_user_intent and last_user_intent.expects_number)
    local parameter_only = is_parameter_only_input(user_input, allow_plain_number)

    if pending_intent then
        if parameter_only then
            if pending_intent.attempted then
                last_error = "One follow-up was already used. Try one complete command."
                append_history("system", "Error: " .. last_error, true)
                set_status("Error: " .. last_error)
                pending_intent = nil
                pending_question = nil
                return
            end
            pending_intent.attempted = true
            local combined = pending_intent.original_cmd .. " " .. user_input
            run_command_flow(combined, pending_intent.forced_target, true)
            if not pending_question and not last_error then
                maybe_speak_feedback(speech_last_response)
            end
            return
        end

        -- User sent a fresh command instead of a numeric fill; clear pending intent.
        pending_intent = nil
        pending_question = nil
        forced_target = nil
        clarification_attempted = false
    end

    if parameter_only and last_user_intent and last_user_intent.expects_number then
        local combined = build_followup_command(last_user_intent, user_input)
        run_command_flow(combined, last_user_intent.forced_target, true)
        if not pending_question and not last_error then
            maybe_speak_feedback(speech_last_response)
        end
        return
    end

    run_command_flow(user_input, nil, false)
    if not pending_question and not last_error then
        maybe_speak_feedback(speech_last_response)
    end
end

local function draw_history(history_height)
    local child_started, child_visible = begin_child_compat("History", -1, history_height, true)
    if child_started then
        local ok, err = pcall(function()
            if child_visible then
                local user_at_bottom = true
                if reaper.ImGui_GetScrollY and reaper.ImGui_GetScrollMaxY then
                    local start_scroll_y = reaper.ImGui_GetScrollY(imgui_ctx)
                    local start_scroll_max = reaper.ImGui_GetScrollMaxY(imgui_ctx)
                    user_at_bottom = (start_scroll_max - start_scroll_y) < 24
                end

                for i = 1, #history do
                    local entry = history[i]
                    local prefix = "Cursor"
                    if entry.role == "user" then
                        prefix = "You"
                    elseif entry.role == "user_voice" then
                        prefix = "You (voice)"
                    end
                    reaper.ImGui_TextWrapped(imgui_ctx, prefix .. ": " .. entry.text)
                    if i < #history then
                        reaper.ImGui_Separator(imgui_ctx)
                    end
                end

                local should_scroll = scroll_history_to_bottom and user_at_bottom
                if should_scroll then
                    reaper.ImGui_SetScrollHereY(imgui_ctx, 1.0)
                end
                scroll_history_to_bottom = false
            end
        end)
        if not ok then
            last_error = "UI history render error: " .. tostring(err)
            set_status("Error: UI history render error")
        end
        reaper.ImGui_EndChild(imgui_ctx)
    end
end

local function draw_header(current_ctx)
    local clip_count = #current_ctx.selected_items
    local track_count = #current_ctx.selected_tracks
    local has_time = current_ctx.time_selection ~= nil and "yes" or "no"

    reaper.ImGui_TextWrapped(
        imgui_ctx,
        string.format(
            "Selected clips: %d | Selected tracks: %d | Time selection: %s | Cursor: %s",
            clip_count,
            track_count,
            has_time,
            format_time(current_ctx.cursor)
        )
    )

    reaper.ImGui_Separator(imgui_ctx)
    local status_text = is_planning and "Thinking..." or status_line
    reaper.ImGui_TextWrapped(imgui_ctx, "Status: " .. status_text)

    if show_dock_hint then
        reaper.ImGui_Separator(imgui_ctx)
        reaper.ImGui_TextWrapped(imgui_ctx, "Tip: drag this tab to REAPER's right docker to dock it as a sidebar.")
        reaper.ImGui_SameLine(imgui_ctx)
        if reaper.ImGui_Button(imgui_ctx, "Dismiss") then
            show_dock_hint = false
            set_extstate(EXTSTATE_DOCK_HINT_KEY, "1")
        end
    end
end

local function draw_pending_question()
    if not pending_question then
        return
    end

    reaper.ImGui_Separator(imgui_ctx)
    if question_is_target_choice(pending_question) then
        reaper.ImGui_TextWrapped(imgui_ctx, pending_question)
        if reaper.ImGui_Button(imgui_ctx, "Apply to Clip(s)") then
            if clarification_attempted then
                last_error = "Clarification already used. Try one complete command."
                append_history("system", "Error: " .. last_error, true)
                set_status("Error: " .. last_error)
                pending_intent = nil
                clear_pending_plan_state()
            elseif pending_intent and pending_intent.original_cmd then
                clarification_attempted = true
                forced_target = "clips"
                pending_intent.forced_target = "clips"
                run_command_flow(pending_intent.original_cmd, "clips", true)
                if not pending_question and not last_error then
                    maybe_speak_feedback(speech_last_response)
                end
            end
        end

        reaper.ImGui_SameLine(imgui_ctx)
        if reaper.ImGui_Button(imgui_ctx, "Apply to Track(s)") then
            if clarification_attempted then
                last_error = "Clarification already used. Try one complete command."
                append_history("system", "Error: " .. last_error, true)
                set_status("Error: " .. last_error)
                pending_intent = nil
                clear_pending_plan_state()
            elseif pending_intent and pending_intent.original_cmd then
                clarification_attempted = true
                forced_target = "tracks"
                pending_intent.forced_target = "tracks"
                run_command_flow(pending_intent.original_cmd, "tracks", true)
                if not pending_question and not last_error then
                    maybe_speak_feedback(speech_last_response)
                end
            end
        end
    else
        reaper.ImGui_TextWrapped(imgui_ctx, pending_question)
    end
end

local function draw_input_bar()
    local run_width = 70
    local clear_width = 60
    local spacing = 12
    local available_width = select(1, reaper.ImGui_GetContentRegionAvail(imgui_ctx))
    available_width = tonumber(available_width) or 260
    local input_width = math.max(120, available_width - run_width - clear_width - spacing)

    if reaper.ImGui_SetNextItemWidth then
        reaper.ImGui_SetNextItemWidth(imgui_ctx, input_width)
    end

    local enter_flag = reaper.ImGui_InputTextFlags_EnterReturnsTrue and reaper.ImGui_InputTextFlags_EnterReturnsTrue() or 0
    local enter_pressed
    enter_pressed, command_input = reaper.ImGui_InputText(imgui_ctx, "##CommandInput", command_input, enter_flag)

    reaper.ImGui_SameLine(imgui_ctx)
    if reaper.ImGui_Button(imgui_ctx, "Run") then
        submit_user_command(command_input, "text")
        command_input = ""
    end

    reaper.ImGui_SameLine(imgui_ctx)
    if reaper.ImGui_Button(imgui_ctx, "Clear") then
        clear_state()
    end

    if enter_pressed then
        submit_user_command(command_input, "text")
        command_input = ""
    end
end

local function process_recorded_voice_audio(audio_path)
    speech_status_line = "Transcribing..."
    set_status("Transcribing...")
    local transcript, stt_error = run_stt(audio_path)
    if not transcript then
        speech_error = normalize_text(stt_error or "Transcription failed.")
        speech_status_line = "Error: " .. speech_error
        append_history("system", "Error: " .. speech_error, true)
        set_status("Error: " .. speech_error)
        return
    end

    speech_status_line = "Transcribed."
    submit_user_command(transcript, "voice")
    if not last_error and not pending_question then
        speech_status_line = "Ran voice command."
    end
end

local function stop_voice_recording(manual_stop)
    if not speech_recording_active then
        return
    end

    local audio_path = speech_recording_audio_path
    local pid_path = speech_recording_pid_path
    local log_path = speech_recording_log_path
    local _, os_lower = get_os_details()
    local pid = nil

    speech_recording_active = false
    speech_recording_started_at = 0
    speech_recording_duration = 0
    speech_recording_audio_path = nil
    speech_recording_pid_path = nil
    speech_recording_log_path = nil

    if pid_path then
        pid = read_pid_from_file(pid_path)
        if pid and manual_stop and not is_windows_os(os_lower) then
            run_shell_command(string.format("kill -INT %d", pid), 3000, false)
        end
        os.remove(pid_path)
    end

    local deadline = reaper.time_precise() + (manual_stop and 1.5 or 1.1)
    while reaper.time_precise() < deadline do
        local alive = pid and process_is_alive(pid) or false
        if audio_path and file_exists(audio_path) then
            local current_size = file_size(audio_path)
            if current_size and current_size > 0 and not alive then
                break
            end
        elseif not alive then
            break
        end
    end

    if pid and process_is_alive(pid) and not is_windows_os(os_lower) then
        run_shell_command(string.format("kill -TERM %d", pid), 2000, false)
    end

    if not audio_path or not file_exists(audio_path) then
        local message = "No recorded audio file was produced."
        if is_macos_os(os_lower) then
            message = message .. "\nOn macOS, check: Settings -> Privacy & Security -> Microphone -> REAPER."
        end
        if log_path and file_exists(log_path) then
            local log_text = trim(read_file(log_path) or "")
            if log_text ~= "" then
                message = message .. "\nRecorder log:\n" .. log_text
            end
            os.remove(log_path)
        end
        speech_error = normalize_text(message)
        speech_status_line = "Error: " .. speech_error
        append_history("system", "Error: " .. speech_error, true)
        set_status("Error: " .. speech_error)
        return
    end

    local size = file_size(audio_path)
    if size and size < 256 then
        os.remove(audio_path)
        local message = "Recorded audio was empty. Try again and speak louder."
        if log_path and file_exists(log_path) then
            local log_text = trim(read_file(log_path) or "")
            if log_text ~= "" then
                message = message .. "\nRecorder log:\n" .. log_text
            end
            os.remove(log_path)
        end
        speech_error = message
        speech_status_line = "Error: " .. speech_error
        append_history("system", "Error: " .. speech_error, true)
        set_status("Error: " .. speech_error)
        return
    end

    if log_path and file_exists(log_path) then
        os.remove(log_path)
    end

    process_recorded_voice_audio(audio_path)
end

local function start_voice_recording_async(duration)
    local output_path = make_temp_path("voice_cmd", "wav")
    local pid_path = make_temp_path("voice_cmd_pid", "txt")
    local log_path = make_temp_path("voice_cmd_log", "txt")
    os.remove(output_path)
    os.remove(pid_path)
    os.remove(log_path)

    local _, os_lower = get_os_details()
    local record_cmd
    if is_macos_os(os_lower) then
        local audio_index = detect_macos_audio_input_index()
        record_cmd = string.format(
            "%s -hide_banner -loglevel error -y -f avfoundation -i %s -t %.2f -ac 1 -ar 16000 %s",
            shell_quote(FFMPEG),
            shell_quote(":" .. tostring(audio_index)),
            duration,
            shell_quote(output_path)
        )
    elseif is_windows_os(os_lower) then
        -- Windows fallback remains synchronous.
        return record_voice_command(duration)
    else
        record_cmd = string.format(
            "%s -hide_banner -loglevel error -y -f pulse -i %s -t %.2f -ac 1 -ar 16000 %s",
            shell_quote(FFMPEG),
            shell_quote("default"),
            duration,
            shell_quote(output_path)
        )
    end

    local background_cmd = string.format("%s > %s 2>&1 & echo $! > %s", record_cmd, shell_quote(log_path), shell_quote(pid_path))
    local quoted_background_cmd = shell_single_quote(background_cmd)
    local launch_attempts = {}
    if file_exists("/bin/zsh") then
        launch_attempts[#launch_attempts + 1] = string.format("/bin/zsh -lc %s", quoted_background_cmd)
    end
    if file_exists("/bin/sh") then
        launch_attempts[#launch_attempts + 1] = string.format("/bin/sh -c %s", quoted_background_cmd)
    end
    if #launch_attempts == 0 then
        launch_attempts[1] = background_cmd
    end

    local diagnostics = {}
    local launched = false
    for i = 1, #launch_attempts do
        local launch_cmd = launch_attempts[i]
        local exit_code, output = reaper.ExecProcess(launch_cmd, 5000)
        if tonumber(exit_code) == 0 then
            local pid_deadline = reaper.time_precise() + 0.5
            while reaper.time_precise() < pid_deadline do
                local pid = read_pid_from_file(pid_path)
                if pid and pid > 0 then
                    launched = true
                    break
                end
            end
            if launched then
                break
            end
            diagnostics[#diagnostics + 1] = string.format("[attempt %d] command exited 0 but pid was not created", i)
        else
            diagnostics[#diagnostics + 1] = string.format(
                "[attempt %d exit=%s] %s",
                i,
                tostring(exit_code),
                tostring(output or "")
            )
        end
    end

    if not launched then
        local err = table.concat(diagnostics, "\n")
        local log_text = trim(read_file(log_path) or "")
        os.remove(pid_path)
        os.remove(output_path)
        os.remove(log_path)
        local message = "Failed to start recording process."
        if err ~= "" then
            message = message .. "\n" .. err
        end
        if log_text ~= "" then
            message = message .. "\nRecorder log:\n" .. log_text
        end
        return nil, message
    end

    speech_recording_active = true
    speech_recording_started_at = reaper.time_precise()
    speech_recording_duration = duration
    speech_recording_audio_path = output_path
    speech_recording_pid_path = pid_path
    speech_recording_log_path = log_path
    return output_path, nil
end

local function update_recording_progress()
    if not speech_recording_active then
        return
    end

    local elapsed = reaper.time_precise() - (speech_recording_started_at or 0)
    if elapsed < 0 then
        elapsed = 0
    end
    local shown = math.min(elapsed, speech_recording_duration)
    speech_status_line = string.format("Recording... %.1fs / %.1fs", shown, speech_recording_duration)

    if elapsed >= speech_recording_duration then
        stop_voice_recording(false)
    end
end

local function run_voice_command()
    if speech_recording_active then
        return
    end

    local duration = tonumber(stt_duration_options[stt_duration_index]) or 5
    speech_error = nil
    set_status("Recording voice command...")

    local _, os_lower = get_os_details()
    if is_windows_os(os_lower) then
        speech_status_line = "Recording..."
        local audio_path, record_error = record_voice_command(duration)
        if not audio_path then
            speech_error = normalize_text(record_error or "Recording failed.")
            speech_status_line = "Error: " .. speech_error
            append_history("system", "Error: " .. speech_error, true)
            set_status("Error: " .. speech_error)
            return
        end
        process_recorded_voice_audio(audio_path)
        return
    end

    local _, start_error = start_voice_recording_async(duration)
    if start_error then
        speech_error = normalize_text(start_error)
        speech_status_line = "Error: " .. speech_error
        append_history("system", "Error: " .. speech_error, true)
        set_status("Error: " .. speech_error)
        return
    end

    speech_status_line = string.format("Recording... 0.0s / %.1fs", duration)
end

local function speak_last_response_now()
    local text = trim(speech_last_response)
    if text == "" then
        speech_error = "No response available to speak yet."
        speech_status_line = "Error: " .. speech_error
        set_status("Error: " .. speech_error)
        return
    end

    speech_error = nil
    speech_status_line = "Synthesizing..."
    local mp3_path, tts_error = run_tts(text, speech_voice_override)
    if not mp3_path then
        speech_error = normalize_text(tts_error or "TTS failed.")
        speech_status_line = "Error: " .. speech_error
        append_history("system", "Error: " .. speech_error, true)
        set_status("Error: " .. speech_error)
        return
    end

    local play_error = play_tts_file(mp3_path)
    if play_error then
        speech_error = normalize_text(play_error)
        speech_status_line = "Saved speech file (auto-play failed)."
        return
    end
    speech_status_line = "Played last response."
end

local function draw_commands_tab()
    local available_height = select(2, reaper.ImGui_GetContentRegionAvail(imgui_ctx))
    available_height = tonumber(available_height) or 520
    local history_height = math.max(120, available_height - 110)
    draw_history(history_height)
    draw_pending_question()
    reaper.ImGui_Separator(imgui_ctx)
    draw_input_bar()
end

local function draw_speech_tab()
    reaper.ImGui_Text(imgui_ctx, "Voice command")
    reaper.ImGui_Separator(imgui_ctx)

    if detect_ffmpeg() then
        reaper.ImGui_TextWrapped(imgui_ctx, "Record a short command and run it through the same Gemini command pipeline.")
    else
        reaper.ImGui_TextWrapped(imgui_ctx, "Recording requires ffmpeg at: " .. FFMPEG)
    end

    reaper.ImGui_Text(imgui_ctx, "Recording length")
    reaper.ImGui_SameLine(imgui_ctx)
    if reaper.ImGui_BeginDisabled and reaper.ImGui_EndDisabled then
        reaper.ImGui_BeginDisabled(imgui_ctx, speech_recording_active)
        if reaper.ImGui_BeginCombo and reaper.ImGui_EndCombo then
            local current_label = tostring(stt_duration_options[stt_duration_index] or 5) .. "s"
            if reaper.ImGui_BeginCombo(imgui_ctx, "##stt_duration", current_label) then
                for i = 1, #stt_duration_options do
                    local label = tostring(stt_duration_options[i]) .. "s"
                    local selected = i == stt_duration_index
                    if reaper.ImGui_Selectable(imgui_ctx, label, selected) then
                        stt_duration_index = i
                    end
                    if selected and reaper.ImGui_SetItemDefaultFocus then
                        reaper.ImGui_SetItemDefaultFocus(imgui_ctx)
                    end
                end
                reaper.ImGui_EndCombo(imgui_ctx)
            end
        end
        reaper.ImGui_EndDisabled(imgui_ctx)
    end

    local _, speech_os_lower = get_os_details()
    if is_macos_os(speech_os_lower) then
        reaper.ImGui_TextWrapped(imgui_ctx, "Audio input index (macOS, optional)")
        if reaper.ImGui_SetNextItemWidth then
            reaper.ImGui_SetNextItemWidth(imgui_ctx, 120)
        end
        local changed_input_idx, next_input_idx = reaper.ImGui_InputText(imgui_ctx, "##speech_input_index", speech_audio_device_override)
        if changed_input_idx then
            speech_audio_device_override = trim(next_input_idx or "")
            macos_audio_input_index_cache = nil
        end
        local selected_index = detect_macos_audio_input_index()
        reaper.ImGui_SameLine(imgui_ctx)
        reaper.ImGui_Text(imgui_ctx, "Using: " .. tostring(selected_index))
    end

    if speech_recording_active then
        reaper.ImGui_TextWrapped(imgui_ctx, "Recording now...")
    end

    local record_disabled = (not detect_ffmpeg()) or speech_recording_active
    if speech_recording_active then
        if reaper.ImGui_Button(imgui_ctx, "Stop Recording") then
            stop_voice_recording(true)
        end
    else
        if reaper.ImGui_BeginDisabled and reaper.ImGui_EndDisabled then
            reaper.ImGui_BeginDisabled(imgui_ctx, record_disabled)
            if reaper.ImGui_Button(imgui_ctx, "Start Recording") then
                run_voice_command()
            end
            reaper.ImGui_EndDisabled(imgui_ctx)
        elseif not record_disabled then
            if reaper.ImGui_Button(imgui_ctx, "Start Recording") then
                run_voice_command()
            end
        else
            reaper.ImGui_Button(imgui_ctx, "Start Recording")
        end
    end

    reaper.ImGui_TextWrapped(imgui_ctx, "Speech status: " .. speech_status_line)

    reaper.ImGui_Separator(imgui_ctx)
    reaper.ImGui_Text(imgui_ctx, "Spoken feedback")
    local _, next_speak = checkbox_compat("Speak after running a command", speak_after_run)
    speak_after_run = next_speak

    if reaper.ImGui_Button(imgui_ctx, "Speak last response") then
        speak_last_response_now()
    end

    local env_voice_id = trim(os.getenv("ELEVENLABS_VOICE_ID") or "")
    if env_voice_id == "" then
        env_voice_id = "(not set, will auto-discover)"
    end
    reaper.ImGui_TextWrapped(imgui_ctx, "Default voice ID: " .. env_voice_id)
    reaper.ImGui_TextWrapped(imgui_ctx, "Voice ID override (optional)")
    if reaper.ImGui_SetNextItemWidth then
        reaper.ImGui_SetNextItemWidth(imgui_ctx, -1)
    end
    local changed, next_voice = reaper.ImGui_InputText(imgui_ctx, "##voice_override", speech_voice_override)
    if changed then
        speech_voice_override = next_voice
    end

    if speech_error and trim(speech_error) ~= "" then
        reaper.ImGui_Separator(imgui_ctx)
        reaper.ImGui_TextWrapped(imgui_ctx, "Speech error: " .. speech_error)
    end
end

local function draw_ui()
    local pushed_style = 0
    if reaper.ImGui_PushStyleVar and reaper.ImGui_StyleVar_WindowPadding then
        reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_WindowPadding(), 12, 10)
        pushed_style = pushed_style + 1
    end
    if reaper.ImGui_PushStyleVar and reaper.ImGui_StyleVar_FramePadding then
        reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 6)
        pushed_style = pushed_style + 1
    end
    if reaper.ImGui_PushStyleVar and reaper.ImGui_StyleVar_ItemSpacing then
        reaper.ImGui_PushStyleVar(imgui_ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 8)
        pushed_style = pushed_style + 1
    end

    local current_ctx = collect_context()
    draw_header(current_ctx)
    reaper.ImGui_Separator(imgui_ctx)

    local drew_tabs = false
    if reaper.ImGui_BeginTabBar and reaper.ImGui_EndTabBar and reaper.ImGui_BeginTabItem and reaper.ImGui_EndTabItem then
        if reaper.ImGui_BeginTabBar(imgui_ctx, "CursorTabs") then
            drew_tabs = true
            if reaper.ImGui_BeginTabItem(imgui_ctx, "Commands") then
                draw_commands_tab()
                reaper.ImGui_EndTabItem(imgui_ctx)
            end
            if reaper.ImGui_BeginTabItem(imgui_ctx, "Speech") then
                draw_speech_tab()
                reaper.ImGui_EndTabItem(imgui_ctx)
            end
            reaper.ImGui_EndTabBar(imgui_ctx)
        end
    end

    if not drew_tabs then
        draw_commands_tab()
        reaper.ImGui_Separator(imgui_ctx)
        draw_speech_tab()
    end

    if reaper.ImGui_PopStyleVar and pushed_style > 0 then
        reaper.ImGui_PopStyleVar(imgui_ctx, pushed_style)
    end
end

local function loop()
    if not imgui_ctx then
        return
    end

    update_recording_progress()

    local ok, open_or_err = pcall(function()
        local cond_first = reaper.ImGui_Cond_FirstUseEver and reaper.ImGui_Cond_FirstUseEver() or 0
        reaper.ImGui_SetNextWindowSize(imgui_ctx, 420, 820, cond_first)
        reaper.ImGui_SetNextWindowPos(imgui_ctx, 1040, 40, cond_first)

        if autodock_pending then
            autodock_pending = false
            set_extstate(EXTSTATE_AUTODOCK_KEY, "1")

            -- Best-effort auto-dock attempt. On most setups this will still require
            -- dragging the tab into REAPER's right docker once.
            if reaper.ImGui_SetNextWindowDockID and reaper.ImGui_GetID then
                local ok_id, dock_id = pcall(reaper.ImGui_GetID, imgui_ctx, "CursorForDAWs_RightSidebarDock")
                if ok_id and type(dock_id) == "number" then
                    pcall(reaper.ImGui_SetNextWindowDockID, imgui_ctx, dock_id, cond_first)
                end
            end
        end

        local visible, open = reaper.ImGui_Begin(imgui_ctx, WINDOW_TITLE, true)
        if visible then
            draw_ui()
            reaper.ImGui_End(imgui_ctx)
        end
        return open
    end)

    if not ok then
        pcall(reaper.ShowMessageBox, "Cursor panel UI error:\n" .. tostring(open_or_err), "Cursor for DAWs", 0)
        pcall(reaper.ImGui_DestroyContext, imgui_ctx)
        imgui_ctx = nil
        return
    end

    if open_or_err then
        reaper.defer(loop)
        return
    end

    pcall(reaper.ImGui_DestroyContext, imgui_ctx)
    imgui_ctx = nil
end

loop()

-- AI Audio Control ReaScript
-- Works with selected track and selected media item

-----------------------------------
-- Utility: Get Current Context
-----------------------------------
function get_context()

    local track = reaper.GetSelectedTrack(0,0)
    local item = reaper.GetSelectedMediaItem(0,0)

    local track_name = "None"
    local item_length = 0

    if track then
        retval, track_name = reaper.GetTrackName(track)
    end

    if item then
        item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    end

    reaper.ShowConsoleMsg("Track: "..track_name.."\n")
    reaper.ShowConsoleMsg("Item Length: "..item_length.."\n")

    return track, item
end

-----------------------------------
-- Volume Control (dB)
-----------------------------------
function volume(db_change)

    local track = reaper.GetSelectedTrack(0,0)

    if not track then
        reaper.ShowConsoleMsg("No track selected\n")
        return
    end

    local currentVol =
        reaper.GetMediaTrackInfo_Value(track,"D_VOL")

    local db =
        20 * math.log(currentVol,10)

    local new_db =
        db + db_change

    local newVol =
        10^(new_db/20)

    reaper.SetMediaTrackInfo_Value(
        track,
        "D_VOL",
        newVol
    )

    reaper.ShowConsoleMsg(
        "Volume changed by "
        ..db_change..
        " dB\n"
    )
end

-----------------------------------
-- Pan Control
-----------------------------------
function pan(value)

    local track = reaper.GetSelectedTrack(0,0)

    if not track then
        reaper.ShowConsoleMsg("No track selected\n")
        return
    end

    if value > 1 then value = 1 end
    if value < -1 then value = -1 end

    reaper.SetMediaTrackInfo_Value(
        track,
        "D_PAN",
        value
    )

    reaper.ShowConsoleMsg(
        "Pan set to "..value.."\n"
    )
end

-----------------------------------
-- Add Compressor
-----------------------------------
function add_compressor()

    local track = reaper.GetSelectedTrack(0,0)

    if not track then
        reaper.ShowConsoleMsg("No track selected\n")
        return
    end

    reaper.TrackFX_AddByName(
        track,
        "ReaComp (Cockos)",
        false,
        -1
    )

    reaper.ShowConsoleMsg(
        "Compressor added\n"
    )
end

-----------------------------------
-- Fade Out Selected Item
-----------------------------------
function fade_out(seconds)

    local item =
        reaper.GetSelectedMediaItem(0,0)

    if not item then
        reaper.ShowConsoleMsg(
        "No item selected\n")
        return
    end

    local length =
        reaper.GetMediaItemInfo_Value(
            item,
            "D_LENGTH"
        )

    if seconds > length then
        seconds = length
    end

    reaper.SetMediaItemInfo_Value(
        item,
        "D_FADEOUTLEN",
        seconds
    )

    reaper.UpdateArrange()

    reaper.ShowConsoleMsg(
        "Fade out set to "
        ..seconds.." sec\n"
    )
end

-----------------------------------
-- Fade In Selected Item
-----------------------------------
function fade_in(seconds)

    local item =
        reaper.GetSelectedMediaItem(0,0)

    if not item then
        reaper.ShowConsoleMsg(
        "No item selected\n")
        return
    end

    local length =
        reaper.GetMediaItemInfo_Value(
            item,
            "D_LENGTH"
        )

    if seconds > length then
        seconds = length
    end

    reaper.SetMediaItemInfo_Value(
        item,
        "D_FADEINLEN",
        seconds
    )

    reaper.UpdateArrange()

    reaper.ShowConsoleMsg(
        "Fade in set to "
        ..seconds.." sec\n"
    )
end

-----------------------------------
-- Mute Track
-----------------------------------
function mute(state)

    local track =
        reaper.GetSelectedTrack(0,0)

    if not track then
        reaper.ShowConsoleMsg(
        "No track selected\n")
        return
    end

    if state then
        value = 1
    else
        value = 0
    end

    reaper.SetMediaTrackInfo_Value(
        track,
        "B_MUTE",
        value
    )

    reaper.ShowConsoleMsg(
        "Mute = "..value.."\n"
    )
end

-----------------------------------
-- Solo Track
-----------------------------------
function solo(state)

    local track =
        reaper.GetSelectedTrack(0,0)

    if not track then
        reaper.ShowConsoleMsg(
        "No track selected\n")
        return
    end

    if state then
        value = 1
    else
        value = 0
    end

    reaper.SetMediaTrackInfo_Value(
        track,
        "I_SOLO",
        value
    )

    reaper.ShowConsoleMsg(
        "Solo = "..value.."\n"
    )
end

-----------------------------------
-- Example Calls (Test Section)
-----------------------------------

reaper.ShowConsoleMsg("SCRIPT RUNNING\n\n")

get_context()

-- Try changing these:

-- volume(2)
-- pan(-0.5)
-- add_compressor()
-- fade_out(2)
-- fade_in(1)
-- mute(true)
-- solo(true)
obs = obslua

-- User settings
srt_file_path = ""
text_source_name = "TeleprompterText"
current_subtitle = ""
subtitles = {}
subtitles_start_time = 0
recording_start_time = nil
prev_text = nil
cur_subtitle = nil
next_subtitle = nil
next_subtitle_idx = 1

function script_description()
    return "Displays subtitles from an SRT file as a teleprompter in OBS."
end

function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_path(props, "srt_file_path", "SRT File", obs.OBS_PATH_FILE, "*.srt", nil)
    obs.obs_properties_add_text(props, "text_source_name", "Text Source Name", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "subtitles_start_time", "Subtitles Start Time HH:MM:SS,mmm", obs.OBS_TEXT_DEFAULT)
    return props
end

function script_update(settings)
    srt_file_path = obs.obs_data_get_string(settings, "srt_file_path")
    text_source_name = obs.obs_data_get_string(settings, "text_source_name")
    load_srt_file()
    subtitles_start_time_str = obs.obs_data_get_string(settings, "subtitles_start_time")
    if subtitles_start_time_str and #subtitles_start_time_str > 0 then
        subtitles_start_time = parse_time(obs.obs_data_get_string(settings, "subtitles_start_time"))
    else
        subtitles_start_time = 0
    end
    next_subtitle_idx = 1
end

function load_srt_file()
    subtitles = {}
    local file = io.open(srt_file_path, "r")
    if not file then 
        return 
    end
    
    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()
    
    local i = 1
    while i <= #lines do
        local timestamp = lines[i + 1]
        local text = {}
        local j = i + 2
        while j <= #lines and lines[j] ~= "" do
            table.insert(text, lines[j])
            j = j + 1
        end
        
        if timestamp and #text > 0 then
            local start_time = parse_time(timestamp:match("(%d%d:%d%d:%d%d,%d%d%d)"))
            local end_time = parse_time(timestamp:match("--> (%d%d:%d%d:%d%d,%d%d%d)"))
            table.insert(subtitles, {start_time = start_time, end_time = end_time, text = table.concat(text, " ")})
        end
        
        i = j + 1
    end
end

function parse_time(timestamp)
    local h, m, s, ms = timestamp:match("(%d%d):(%d%d):(%d%d),(%d%d%d)")
    if h and m and s and ms then
        return (tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)) * 1000 + tonumber(ms)
    else
        return 0
    end
end

function update_subtitle()
    local is_recording = obs.obs_frontend_recording_active()
    local current_time = obs.os_gettime_ns() / 1000000 -- os.time() * 1000
    local possible_prev_subtitle = nil
    local found_cur_subtitle = false
    local cur_subtitle_remaining_time = 0
    local elapsed_time = nil

    if is_recording and next_subtitle then
        if not recording_start_time then
            recording_start_time = current_time + 3000 - subtitles_start_time -- Store recording start time
        end
        
        elapsed_time = current_time - recording_start_time

        -- Update subtitles based on elapsed time
        --for _, subtitle in ipairs(subtitles) do
        if elapsed_time >= next_subtitle.start_time then
            if cur_subtitle then
                prev_text = cur_subtitle.text
            end
            cur_subtitle = next_subtitle

            if next_subtitle_idx <= #subtitles then
                next_subtitle_idx = next_subtitle_idx + 1
                next_subtitle = subtitles[next_subtitle_idx]
            else
                next_subtitle = nil
            end
        end
    else
        -- Reset when recording stops
        recording_start_time = nil
        prev_text = nil
        cur_subtitle = nil
        if next_subtitle_idx > #subtitles then
            next_subtitle_idx = 1
        end
        local subtitle = subtitles[next_subtitle_idx]
        while next_subtitle_idx > 1 and subtitle.start_time > subtitles_start_time do
            next_subtitle_idx = next_subtitle_idx - 1
            subtitle = subtitles[next_subtitle_idx]
        end
        while next_subtitle_idx < #subtitles and subtitle.start_time < subtitles_start_time do
            next_subtitle_idx = next_subtitle_idx + 1
            subtitle = subtitles[next_subtitle_idx]
        end
        next_subtitle = subtitle
    end

    set_text_source("prev " .. text_source_name, prev_text)
    if cur_subtitle then
        cur_subtitle_remaining_time = cur_subtitle.end_time - elapsed_time
        set_text_source(text_source_name, format_timing(cur_subtitle_remaining_time) .. cur_subtitle.text)
    else
        set_text_source(text_source_name, "...")
    end
    if next_subtitle and elapsed_time then
        set_text_source("next " .. text_source_name, format_timing(next_subtitle.start_time - elapsed_time) .. next_subtitle.text)
    else
        set_text_source("next " .. text_source_name, nil)
    end
end

function format_timing(time)
    if time < 0 then
        return "[-.-] "
    end

    local sec = math.floor(time / 1000)
    local tenths = math.floor(time / 100) % 10
    return "[" .. tostring(sec) .. "." .. tostring(tenths) .. "] "
end

function set_text_source(name, text)
    if not text then 
        text = "..." 
    end

    local source = obs.obs_get_source_by_name(name)
    if source then
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, "text", text)
        obs.obs_source_update(source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(source)
    end
end

function script_tick(seconds)
    update_subtitle()
end

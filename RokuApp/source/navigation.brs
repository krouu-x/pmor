' Shared UI helpers (included by screens).
function NodeText(v as dynamic) as string
    if v = invalid then return ""
    t = type(v)
    if t = "roString" or t = "String" then return v
    if t = "roInt" or t = "roFloat" or t = "Integer" or t = "Float" or t = "roBoolean" or t = "Boolean" or t = "Double" or t = "roDouble" or t = "LongInteger" then return v.ToStr()
    return ""
end function

function Rating(v as dynamic) as string
    if v = invalid then return ""
    if v <= 0 then return ""
    return "★ " + (Int(v * 10 + 0.5) / 10).ToStr()
end function

function JoinParts(parts as object, sep = "   •   " as string) as string
    s = ""
    for each p in parts
        if p <> "" then
            if s <> "" then s += sep
            s += p
        end if
    end for
    return s
end function

function JoinNames(arr as dynamic) as string
    s = ""
    if arr = invalid then return s
    for each x in arr
        if s <> "" then s += ", "
        s += NodeText(x.name)
    end for
    return s
end function

function PosterUrl(path as dynamic, kind = "poster" as string) as string
    u = ImageUrl(path, kind)
    if u = "" then return "pkg:/images/placeholder.png"
    return u
end function

function ItemNode(raw as object, kind as string) as object
    if raw.media_type <> invalid then kind = raw.media_type
    n = CreateObject("roSGNode", "ContentNode")
    title = raw.title
    if title = invalid then title = raw.name
    date = raw.release_date
    if date = invalid then date = raw.first_air_date
    subtitle = JoinParts([Left(NodeText(date), 4), Rating(raw.vote_average)], "   ")
    if raw.character <> invalid then subtitle = NodeText(raw.character)
    if raw.episode_count <> invalid then subtitle = raw.episode_count.ToStr() + " episodes"
    path = raw.poster_path
    if path = invalid then path = raw.profile_path
    sn = 0
    if raw.season_number <> invalid then sn = raw.season_number
    n.addFields({ mt: kind, tid: raw.id, sn: sn, bg: ImageUrl(raw.backdrop_path, "backdrop"), ov: NodeText(raw.overview) })
    n.title = NodeText(title)
    n.ShortDescriptionLine1 = subtitle
    n.HDPosterUrl = PosterUrl(path)
    return n
end function

function FavNode(f as object) as object
    n = CreateObject("roSGNode", "ContentNode")
    n.addFields({ mt: f.mt, tid: f.tid, sn: 0, bg: f.bg, ov: "" })
    n.title = f.title
    n.ShortDescriptionLine1 = f.subtitle
    n.HDPosterUrl = f.poster
    return n
end function

function MakeReq(r as object) as object
    r.nonce = Rnd(0)
    return r
end function

' Starts a BatchTask; the calling component must define onResults() and onApiError().
sub StartBatch(reqs as object)
    m.task = CreateObject("roSGNode", "BatchTask")
    m.task.observeField("results", "onResults")
    m.task.observeField("error", "onApiError")
    m.task.requests = reqs
    m.task.control = "RUN"
end sub

' Picks the best YouTube key from a TMDB /videos "results" array ("" if none).
function PickTrailer(arr as dynamic) as string
    best = ""
    rank = 0
    if arr = invalid then return best
    for each v in arr
        if v.site = "YouTube" and v.key <> invalid then
            score = 1
            if v.type = "Teaser" then score = 2
            if v.type = "Trailer" then score = 3
            if v.official = true then score += 1
            if score > rank then
                rank = score
                best = v.key
            end if
        end if
    end for
    return best
end function

' Opens the official YouTube channel on this Roku at the given video (screen must define onLaunchStatus).
sub StartLaunch(videoKey as string)
    m.launch = CreateObject("roSGNode", "LaunchTask")
    m.launch.observeField("status", "onLaunchStatus")
    m.launch.videoKey = videoKey
    m.launch.control = "RUN"
end sub

sub StartService(paths as object, callback as string)
    m.svc = CreateObject("roSGNode", "ServiceTask")
    m.svc.observeField("results", callback)
    m.svc.paths = paths
    m.svc.control = "RUN"
end sub

' Finds the first playable-looking http(s) URL in whatever JSON your server returns.
function FindStreamUrl(v as dynamic, depth = 0 as integer) as string
    if v = invalid or depth > 6 then return ""
    t = type(v)
    if t = "roString" or t = "String" then
        if Left(v, 4) = "http" then
            ' Only accept Roku-playable formats: HLS (.m3u8) or MP4
            vl = LCase(v)
            if Right(vl, 5) = ".m3u8" or Right(vl, 4) = ".mp4" then
                return v
            end if
        end if
        return ""
    end if
    if t = "roAssociativeArray" then
        ' Priority order: prefer HLS, then MP4
        for each k in ["url", "file", "src", "stream", "streamUrl", "link", "playlist", "hls", "m3u8", "mp4", "raw"]
            if v[k] <> invalid then
                r = FindStreamUrl(v[k], depth + 1)
                if r <> "" then return r
            end if
        end for
        for each k in v
            r = FindStreamUrl(v[k], depth + 1)
            if r <> "" then return r
        end for
    else if t = "roArray" then
        for each x in v
            r = FindStreamUrl(x, depth + 1)
            if r <> "" then return r
        end for
    end if
    return ""
end function

function FindStreamWithHeaders(v as dynamic, depth = 0 as integer) as object
    if v = invalid or depth > 6 then return invalid
    t = type(v)
    if t = "roAssociativeArray" then
        ' Check if this object has a "url" field with playable format
        if v.url <> invalid then
            u = v.url
            if type(u) = "roString" or type(u) = "String" then
                vl = LCase(u)
                ' Check if URL CONTAINS .m3u8 or .mp4 (not just ends with, due to query params)
                if (Instr(1, vl, ".m3u8") > 0 or Instr(1, vl, ".mp4") > 0) and Left(u, 4) = "http" then
                    h = v.headers
                    if h = invalid then h = {}
                    return { url: u, headers: h }
                end if
            end if
        end if
        ' Recurse into known fields first
        for each k in ["url", "file", "src", "stream", "streamUrl", "link", "playlist", "hls", "m3u8", "mp4", "raw", "streams", "results"]
            if v[k] <> invalid then
                r = FindStreamWithHeaders(v[k], depth + 1)
                if r <> invalid and r.url <> "" then return r
            end if
        end for
        ' Recurse all fields
        for each k in v
            r = FindStreamWithHeaders(v[k], depth + 1)
            if r <> invalid and r.url <> "" then return r
        end for
    else if t = "roArray" then
        for each x in v
            r = FindStreamWithHeaders(x, depth + 1)
            if r <> invalid and r.url <> "" then return r
        end for
    end if
    return invalid
end function

function Summarize(d as dynamic) as string
    s = ""
    if type(d) = "roAssociativeArray" then
        n = 0
        for each k in d
            t = NodeText(d[k])
            if t = "" then t = Left(FormatJson(d[k]), 70)
            s += "    " + k + ": " + t + chr(10)
            n++
            if n >= 6 then exit for
        end for
    else if d <> invalid then
        s = "    " + Left(FormatJson(d), 120) + chr(10)
    end if
    return s
end function

function Pad2(n as integer) as string
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
end function

function FormatTime(total as dynamic) as string
    if total = invalid then return "0:00"
    s = Int(total)
    if s < 0 then s = 0
    h = Int(s / 3600)
    mn = Int((s - h * 3600) / 60)
    sc = s - h * 3600 - mn * 60
    if h > 0 then return h.ToStr() + ":" + Pad2(mn) + ":" + Pad2(sc)
    return mn.ToStr() + ":" + Pad2(sc)
end function

sub init()
    m.rows = m.top.findNode("rows")
    m.play = m.top.findNode("play")
    m.watch = m.top.findNode("watch")
    m.watch.observeField("buttonSelected", "onWatch")
    m.play.observeField("buttonSelected", "onPlay")
    m.trailerKey = ""
    m.root = CreateObject("roSGNode", "ContentNode")
    m.rows.content = m.root
    m.rows.observeField("rowItemSelected", "onSelected")
    m.handled = {}
    m.rowNodes = {}
    m.infoBase = ""
    m.director = ""
end sub

sub onTarget()
    t = m.top.target
    m.mt = t.mt
    m.id = t.id
    labels = [["cast", "Cast"]]
    if m.mt = "tv" then labels.push(["seasons", "Seasons"])
    labels.push(["rec", "Recommended"])
    labels.push(["sim", "Similar"])
    for each l in labels
        r = m.root.createChild("ContentNode")
        r.title = l[1]
        m.rowNodes[l[0]] = r
    end for
    base = "/" + m.mt + "/" + m.id.ToStr()
    StartBatch([{ key: "d", endpoint: base }, { key: "c", endpoint: base + "/credits" }, { key: "rec", endpoint: base + "/recommendations" }, { key: "sim", endpoint: base + "/similar" }, { key: "v", endpoint: base + "/videos" }])
    updateFav(FavHas(m.mt, m.id))
end sub

sub onResults()
    res = m.task.results
    for each key in res
        if not m.handled.doesExist(key) then
            m.handled[key] = true
            d = res[key]
            if key = "d" then
                showDetails(d)
            else if key = "c" then
                fillRow("cast", d.cast, "person", 20)
                dirs = []
                if d.crew <> invalid then
                    for each p in d.crew
                        if p.job = "Director" then dirs.push({ name: p.name })
                    end for
                end if
                m.director = JoinNames(dirs)
                refreshInfo()
            else if key = "v" then
                m.trailerKey = PickTrailer(d.results)
            else
                fillRow(key, d.results, m.mt, 20)
            end if
        end if
    end for
end sub

sub onApiError()
    m.top.findNode("msg").text = m.task.error
end sub

sub fillRow(key as string, arr as dynamic, kind as string, max as integer)
    row = m.rowNodes[key]
    list = []
    if arr <> invalid then
        for each it in arr
            list.push(ItemNode(it, kind))
            if list.count() >= max then exit for
        end for
    end if
    if list.count() = 0 then
        m.root.removeChild(row)
    else
        row.appendChildren(list)
    end if
end sub

sub showDetails(d as object)
    title = d.title
    if title = invalid then title = d.name
    m.title = NodeText(title)
    orig = d.original_title
    if orig = invalid then orig = d.original_name
    m.top.findNode("dtitle").text = m.title
    m.top.findNode("poster").uri = PosterUrl(d.poster_path)
    m.top.findNode("bg").uri = PosterUrl(d.backdrop_path, "backdrop")
    m.top.findNode("dgenres").text = JoinNames(d.genres)
    m.top.findNode("dover").text = NodeText(d.overview)
    votes = ""
    if d.vote_count <> invalid then votes = "(" + d.vote_count.ToStr() + " votes)"
    rate = JoinParts([Rating(d.vote_average), votes], " ")
    lang = "Language: " + UCase(NodeText(d.original_language))
    prod = "Production: " + JoinNames(d.production_companies)
    if m.mt = "movie" then
        runtime = ""
        if d.runtime <> invalid then runtime = d.runtime.ToStr() + " min"
        m.top.findNode("dmeta").text = JoinParts([NodeText(d.release_date), runtime, rate])
        m.infoBase = JoinParts([lang, prod, "Countries: " + JoinNames(d.production_countries)], "     ")
        date = NodeText(d.release_date)
    else
        span = NodeText(d.first_air_date)
        if d.last_air_date <> invalid then span += " – " + NodeText(d.last_air_date)
        m.top.findNode("dmeta").text = JoinParts([span, NodeText(d.number_of_seasons) + " seasons", NodeText(d.number_of_episodes) + " episodes", rate])
        m.infoBase = JoinParts(["Creators: " + JoinNames(d.created_by), lang, prod], "     ")
        date = NodeText(d.first_air_date)
        fillRow("seasons", d.seasons, "season", 40)
    end if
    m.top.findNode("dsub").text = "Original title: " + NodeText(orig)
    refreshInfo()
    m.entry = { mt: m.mt, tid: m.id, title: m.title, subtitle: JoinParts([Left(date, 4), Rating(d.vote_average)], "   "), poster: PosterUrl(d.poster_path), bg: PosterUrl(d.backdrop_path, "backdrop") }

    ' Update play button text for TV shows
    if m.mt = "tv" then
        m.play.text = "Play"
    else
        m.play.text = "Play Trailer"
    end if
end sub

sub refreshInfo()
    txt = m.infoBase
    if m.director <> "" then txt = "Director: " + m.director + "     " + txt
    m.top.findNode("dinfo").text = txt
end sub

sub updateFav(isFav as boolean)
    m.top.findNode("dfav").text = iif(isFav, "★ In favorites (* to remove)", "☆ Press * to add to favorites")
end sub

sub onSelected()
    idx = m.rows.rowItemSelected
    n = m.root.getChild(idx[0]).getChild(idx[1])
    if n = invalid then return
    if n.mt = "season" then
        m.top.request = MakeReq({ type: "season", tvId: m.id, season: n.sn, name: m.title })
    else if n.mt = "movie" or n.mt = "tv" then
        m.top.request = MakeReq({ type: "title", mt: n.mt, id: n.tid })
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "options" and m.entry <> invalid then
        updateFav(FavToggle(m.mt, m.entry))
        return true
    else if key = "down" and (m.play.hasFocus() or m.watch.hasFocus()) and m.root.getChildCount() > 0 then
        m.rows.setFocus(true)
        return true
    else if key = "up" and m.rows.hasFocus() and m.rows.rowItemFocused[0] = 0 then
        m.watch.setFocus(true)
        return true
    else if key = "right" and m.watch.hasFocus() then
        m.play.setFocus(true)
        return true
    else if key = "left" and m.play.hasFocus() then
        m.watch.setFocus(true)
        return true
    end if
    return false
end function

sub onPlay()
    m.top.findNode("pmsg").text = ""
    if m.mt = "tv" then
        ' For TV shows, play the show (season 1 episode 1) like the watch button
        path = "/api/streams/series/" + m.id.ToStr() + "?season=1&episode=1"
        m.top.findNode("pmsg").text = "Loading stream..."
        StartService([path], "onServiceResults")
    else
        ' For movies, play trailer
        if m.trailerKey = "" then
            m.top.findNode("pmsg").text = "No trailer available."
            return
        end if
        m.play.text = "Opening YouTube..."
        StartLaunch(m.trailerKey)
    end if
end sub

sub onLaunchStatus(ev as object)
    if m.mt = "tv" then
        m.play.text = "Play"
    else
        m.play.text = "Play Trailer"
    end if
    if ev.getData() <> "ok" then m.top.findNode("pmsg").text = ev.getData()
end sub

sub onWatch()
    streamType = m.mt
    if streamType = "tv" then streamType = "series"
    path = "/api/streams/" + streamType + "/" + m.id.ToStr()
    if m.mt = "tv" then path += "?season=1&episode=1"
    m.top.findNode("pmsg").text = "Loading stream..."
    StartService([path], "onServiceResults")
end sub

sub onServiceResults(ev as object)
    res = ev.getData()
    for each key in res
        r = res[key]
        if r.ok then
            ' Parse full response to get all streams
            data = r.data
            streams = invalid

            ' Try to extract streams array from response
            if data.streams <> invalid then
                streams = data.streams
            else if data.results <> invalid then
                streams = data.results
            else if type(data) = "roArray" then
                streams = data
            end if

            if streams = invalid or streams.count() = 0 then
                m.top.findNode("pmsg").text = "Server returned no playable streams."
            else
                m.top.findNode("pmsg").text = ""
                showStreamOptions(streams)
            end if
        else
            m.top.findNode("pmsg").text = r.error
        end if
    end for
end sub

sub showStreamOptions(streams as object)
    ' Wrap streams with proxy if needed
    cfg = GetConfig()
    wrappedStreams = []
    for i = 0 to streams.count() - 1
        s = streams[i]
        wrapped = { }
        ' Copy all fields from original stream
        for each k in s
            wrapped[k] = s[k]
        end for

        ' Apply proxy to URL if needed
        if s.url <> invalid then
            url = s.url
            isLocalProxy = false
            if cfg.serviceBaseUrl <> "" and cfg.serviceBaseUrl <> invalid then
                if Instr(1, url, cfg.serviceBaseUrl) > 0 then
                    isLocalProxy = true
                end if
            end if

            if not isLocalProxy and cfg.streamProxyBaseUrl <> "" and cfg.streamProxyBaseUrl <> invalid then
                proxyParams = "?url=" + CreateObject("roUrlTransfer").Escape(url)
                if s.headers <> invalid then
                    if s.headers["Referer"] <> invalid then
                        proxyParams += "&referer=" + CreateObject("roUrlTransfer").Escape(s.headers["Referer"])
                    end if
                    if s.headers["User-Agent"] <> invalid then
                        proxyParams += "&ua=" + CreateObject("roUrlTransfer").Escape(s.headers["User-Agent"])
                    end if
                    if s.headers["Origin"] <> invalid then
                        proxyParams += "&origin=" + CreateObject("roUrlTransfer").Escape(s.headers["Origin"])
                    end if
                end if
                wrapped.url = cfg.streamProxyBaseUrl + "/proxy" + proxyParams
            else
                wrapped.url = url
            end if
        end if

        wrappedStreams.push(wrapped)
    end for

    ' Auto-play first playable stream (HLS or MP4)
    playableStream = FindFirstPlayableStream(wrappedStreams)
    if playableStream <> invalid then
        m.top.findNode("pmsg").text = ""
        ' Play the stream directly via PlayerScreen
        m.top.request = MakeReq({
            type: "play",
            url: playableStream.url,
            title: m.title,
            audioTrack: invalid,  ' Will use auto/default
            subtitleTrack: -1,    ' Off by default
            audioTracks: playableStream.audioTracks,
            subtitleTracks: playableStream.subtitleTracks,
            headers: playableStream.headers
        })
    else
        m.top.findNode("pmsg").text = "No playable streams found (need HLS or MP4)"
    end if
end sub

function FindFirstPlayableStream(streams as object) as object
    for i = 0 to streams.count() - 1
        s = streams[i]
        if s.url <> invalid then
            vl = LCase(s.url)
            if (Instr(1, vl, ".m3u8") > 0 or Instr(1, vl, ".mp4") > 0) and Left(s.url, 4) = "http" then
                return s
            end if
        end if
    end for
    return invalid
end function

sub onStreamOptionsRequest(ev as object)
    ' This is called when DetailScreen's own request field changes
    ' Not used for StreamOptionsScreen communication (MainScene handles that)
end sub

sub focusMe()
    m.watch.setFocus(true)
end sub

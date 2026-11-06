sub init()
    m.list = m.top.findNode("list")
    m.play = m.top.findNode("play")
    m.pmsg = m.top.findNode("pmsg")
    m.list.observeField("itemFocused", "onFocused")
    m.list.observeField("itemSelected", "onPlayStream")
    m.play.observeField("buttonSelected", "onPlayEp")
    m.eps = []
    m.handled = {}
    m.seasonKey = ""
    m.showKey = ""
    m.pendingEp = false
end sub

sub onTarget()
    t = m.top.target
    m.showName = t.name
    m.tvId = t.tvId
    m.season = t.season
    base = "/tv/" + t.tvId.ToStr()
    sb = base + "/season/" + t.season.ToStr()
    StartBatch([{ key: "s", endpoint: sb }, { key: "sv", endpoint: sb + "/videos" }, { key: "tv", endpoint: base + "/videos" }])
end sub

sub onResults(ev as object)
    res = ev.getData()
    for each key in res
        if not m.handled.doesExist(key) then
            m.handled[key] = true
            d = res[key]
            if key = "s" then
                showSeason(d)
            else if key = "sv" then
                m.seasonKey = PickTrailer(d.results)
            else if key = "tv" then
                m.showKey = PickTrailer(d.results)
            else if key = "ev" then
                m.pendingEp = false
                resolve(PickTrailer(d.results))
            end if
        end if
    end for
end sub

sub onApiError(ev as object)
    if m.pendingEp then
        m.pendingEp = false
        resolve("")
    else if m.eps.count() = 0 then
        m.top.findNode("msg").text = ev.getData()
    end if
end sub

sub showSeason(d as object)
    m.top.findNode("sname").text = NodeText(d.name)
    m.top.findNode("poster").uri = PosterUrl(d.poster_path)
    m.top.findNode("sover").text = NodeText(d.overview)
    n = 0
    c = CreateObject("roSGNode", "ContentNode")
    if d.episodes <> invalid then
        m.eps = d.episodes
        n = m.eps.count()
        for each e in m.eps
            c.createChild("ContentNode").title = NodeText(e.episode_number) + ".  " + NodeText(e.name)
        end for
    end if
    m.top.findNode("smeta").text = JoinParts([m.showName, NodeText(d.air_date), n.ToStr() + " episodes"])
    m.list.content = c
    if n > 0 then showEp(0)
end sub

sub onFocused()
    showEp(m.list.itemFocused)
end sub

sub showEp(i as integer)
    if i < 0 or i >= m.eps.count() then return
    e = m.eps[i]
    runtime = ""
    if e.runtime <> invalid then runtime = e.runtime.ToStr() + " min"
    m.top.findNode("still").uri = PosterUrl(e.still_path, "still")
    m.top.findNode("etitle").text = "Episode " + NodeText(e.episode_number) + ": " + NodeText(e.name)
    m.top.findNode("emeta").text = JoinParts([NodeText(e.air_date), runtime, Rating(e.vote_average)])
    ov = NodeText(e.overview)
    if ov = "" then ov = "No overview available."
    m.top.findNode("eover").text = ov
    m.pmsg.text = ""
end sub

sub onPlayStream()
    i = m.list.itemFocused
    if i < 0 or i >= m.eps.count() then return
    m.pmsg.text = "Loading stream..."
    m.streamTitle = m.showName + "  S" + m.season.ToStr() + "E" + m.eps[i].episode_number.ToStr()
    StartService(["/api/streams/series/" + m.tvId.ToStr() + "?season=" + m.season.ToStr() + "&episode=" + m.eps[i].episode_number.ToStr()], "onServiceResults")
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
                m.pmsg.text = "Server returned no playable streams."
            else
                m.pmsg.text = ""
                showStreamOptions(streams)
            end if
        else
            m.pmsg.text = r.error
        end if
    end for
end sub

' Play the focused episode's trailer; falls back to the season's, then the show's.
sub onPlayEp()
    i = m.list.itemFocused
    if i < 0 or i >= m.eps.count() then return
    m.pmsg.text = ""
    m.play.text = "Finding trailer..."
    m.pendingEp = true
    m.handled.Delete("ev")
    StartBatch([{ key: "ev", endpoint: "/tv/" + m.tvId.ToStr() + "/season/" + m.season.ToStr() + "/episode/" + m.eps[i].episode_number.ToStr() + "/videos" }])
end sub

sub resolve(epKey as string)
    k = epKey
    src = "episode"
    if k = "" then
        k = m.seasonKey
        src = "season"
    end if
    if k = "" then
        k = m.showKey
        src = "show"
    end if
    if k = "" then
        m.play.text = "Play Trailer"
        m.pmsg.text = "No trailer available."
        return
    end if
    m.play.text = "Opening " + src + " trailer..."
    StartLaunch(k)
end sub

sub onLaunchStatus(ev as object)
    m.play.text = "Play Trailer"
    if ev.getData() <> "ok" then m.pmsg.text = ev.getData()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "right" and m.list.hasFocus() then
        m.play.setFocus(true)
        return true
    else if key = "left" and m.play.hasFocus() then
        m.list.setFocus(true)
        return true
    end if
    return false
end function

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
        m.pmsg.text = ""
        ' Play the stream directly via PlayerScreen
        m.top.request = MakeReq({
            type: "play",
            url: playableStream.url,
            title: m.streamTitle,
            audioTrack: invalid,  ' Will use auto/default
            subtitleTrack: -1,    ' Off by default
            audioTracks: playableStream.audioTracks,
            subtitleTracks: playableStream.subtitleTracks,
            headers: playableStream.headers
        })
    else
        m.pmsg.text = "No playable streams found (need HLS or MP4)"
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

sub focusMe()
    m.list.setFocus(true)
end sub

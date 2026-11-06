sub init()
    m.nav = m.top.findNode("nav")
    m.content = m.top.findNode("content")
    m.overlay = m.top.findNode("overlay")
    m.stack = []
    c = CreateObject("roSGNode", "ContentNode")
    for each t in ["Home", "Movies", "TV Shows", "Search", "Watch history", "Genres", "Favorites", "Settings"]
        c.createChild("ContentNode").title = t
    end for
    m.nav.content = c
    m.nav.observeField("itemSelected", "onNavSelect")
    ShowSection(0)
end sub

sub onNavSelect()
    ShowSection(m.nav.itemSelected)
end sub

sub ShowSection(i as integer)
    names = ["BrowseScreen", "BrowseScreen", "BrowseScreen", "GridScreen", "HistoryScreen", "GridScreen", "BrowseScreen", "SettingsScreen"]
    modes = ["home", "movies", "tv", "search", "history", "genre", "favorites", ""]
    if m.section <> invalid then m.content.removeChild(m.section)
    s = CreateObject("roSGNode", names[i])
    s.observeField("request", "onRequest")
    m.content.appendChild(s)
    if modes[i] <> "" then s.mode = modes[i]
    m.section = s
    s.callFunc("focusMe")
end sub

sub onRequest(ev as object)
    r = ev.getData()
    if r = invalid then return
    if r.type = "title" then
        s = CreateObject("roSGNode", "DetailScreen")
    else if r.type = "season" then
        s = CreateObject("roSGNode", "SeasonScreen")
    else if r.type = "play" then
        s = CreateObject("roSGNode", "PlayerScreen")
    else if r.type = "status" then
        s = CreateObject("roSGNode", "StatusScreen")
    else if r.type = "history" then
        s = CreateObject("roSGNode", "HistoryScreen")
    else if r.type = "overlay" then
        if r.screen = "StreamOptionsScreen" then
            s = CreateObject("roSGNode", "StreamOptionsScreen")
            s.observeField("request", "onOverlayRequest")
            m.overlay.appendChild(s)
            m.stack.push(s)
            s.target = r
            s.callFunc("focusMe")
            return
        else
            return
        end if
    else
        return
    end if
    s.observeField("request", "onRequest")
    if m.stack.count() > 0 then m.stack[m.stack.count() - 1].visible = false
    m.content.visible = false
    m.top.findNode("nav").visible = false
    m.top.findNode("logo").visible = false
    m.overlay.appendChild(s)
    m.stack.push(s)
    s.target = r
    s.callFunc("focusMe")
end sub

sub onOverlayRequest(ev as object)
    r = ev.getData()
    if r = invalid then return

    if r.type = "close" then
        ' User cancelled overlay - pop it
        if m.stack.count() > 0 then
            top = m.stack.pop()
            m.overlay.removeChild(top)
            if m.stack.count() > 0 then
                m.stack[m.stack.count() - 1].visible = true
                m.stack[m.stack.count() - 1].callFunc("focusMe")
            else
                m.content.visible = true
                m.nav.visible = true
                m.top.findNode("logo").visible = true
            end if
        end if
    else if r.type = "play" then
        ' Play selected stream from overlay
        if m.stack.count() > 0 then
            top = m.stack.pop()
            m.overlay.removeChild(top)
        end if

        ' Create PlayerScreen with selected stream
        s = CreateObject("roSGNode", "PlayerScreen")
        s.observeField("request", "onRequest")
        if m.stack.count() > 0 then m.stack[m.stack.count() - 1].visible = false
        m.content.visible = false
        m.top.findNode("nav").visible = false
        m.top.findNode("logo").visible = false
        m.overlay.appendChild(s)
        m.stack.push(s)
        s.target = { type: "play", url: r.stream.url, title: r.title, audioTrack: r.audioTrack, subtitleTrack: r.subtitleTrack }
        s.callFunc("focusMe")
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        if m.stack.count() > 0 then
            top = m.stack.pop()
            if top.subtype() = "PlayerScreen" then top.callFunc("stopPlayback")
            m.overlay.removeChild(top)
            if m.stack.count() > 0 then
                m.stack[m.stack.count() - 1].visible = true
                m.stack[m.stack.count() - 1].callFunc("focusMe")
            else
                m.content.visible = true
                m.nav.visible = true
                m.top.findNode("logo").visible = true
                if m.section.subtype() = "BrowseScreen" then m.section.callFunc("refresh")
                m.section.callFunc("focusMe")
            end if
            return true
        else if not m.nav.isInFocusChain() then
            m.nav.setFocus(true)
            return true
        end if
        return false
    else if key = "left" and m.stack.count() = 0 and not m.nav.isInFocusChain() then
        m.nav.setFocus(true)
        return true
    else if key = "right" and m.nav.isInFocusChain() then
        m.section.callFunc("focusMe")
        return true
    end if
    return false
end function

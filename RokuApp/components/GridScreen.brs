sub init()
    m.grid = m.top.findNode("grid")
    m.kb = m.top.findNode("kb")
    m.glist = m.top.findNode("glist")
    m.msg = m.top.findNode("msg")
    m.gridRoot = CreateObject("roSGNode", "ContentNode")
    m.grid.content = m.gridRoot
    m.grid.observeField("itemSelected", "onSelected")
    m.grid.observeField("itemFocused", "onGridFocus")
    m.top.findNode("deb").observeField("fire", "onDebounce")
    m.handled = {}
    m.page = 1
    m.total = 1
    m.loading = false
    m.gmt = "movie"
    m.query = ""
    m.genreId = ""
end sub

sub onMode()
    head = m.top.findNode("head")
    if m.top.mode = "search" then
        head.text = "Search movies & TV shows"
        m.kb.visible = true
        m.kb.observeField("text", "onText")
        m.msg.text = "Type to search."
    else
        m.glist.visible = true
        m.glist.observeField("itemSelected", "onGenre")
        loadGenres()
    end if
end sub

sub loadGenres()
    m.top.findNode("head").text = "Genres: " + iif(m.gmt = "movie", "Movies", "TV Shows") + "   (press * to switch)"
    m.handled = {}
    StartBatch([{ key: "g", endpoint: "/genre/" + m.gmt + "/list" }])
end sub

sub loadPage()
    m.handled = {}
    m.loading = true
    if m.top.mode = "search" then
        StartBatch([{ key: "p", endpoint: "/search/multi", params: { query: m.query, page: m.page } }])
    else
        StartBatch([{ key: "p", endpoint: "/discover/" + m.gmt, params: { with_genres: m.genreId, page: m.page, sort_by: "popularity.desc" } }])
    end if
end sub

sub resetGrid(text as string)
    m.gridRoot.removeChildrenIndex(m.gridRoot.getChildCount(), 0)
    m.page = 1
    m.total = 1
    m.msg.text = text
end sub

sub onText()
    m.top.findNode("deb").control = "stop"
    m.top.findNode("deb").control = "start"
end sub

sub onDebounce()
    q = m.kb.text
    if q = m.query then return
    m.query = q
    if q = "" then
        resetGrid("Type to search.")
        return
    end if
    resetGrid("Searching...")
    loadPage()
end sub

sub onGenre()
    n = m.glist.content.getChild(m.glist.itemSelected)
    m.genreId = n.id
    resetGrid("Loading...")
    loadPage()
end sub

sub onResults()
    res = m.task.results
    for each key in res
        if not m.handled.doesExist(key) then
            m.handled[key] = true
            d = res[key]
            if key = "g" then
                c = CreateObject("roSGNode", "ContentNode")
                for each g in d.genres
                    n = c.createChild("ContentNode")
                    n.title = g.name
                    n.id = g.id.ToStr()
                end for
                m.glist.content = c
                if m.gridRoot.getChildCount() = 0 then m.msg.text = "Pick a genre."
            else
                m.loading = false
                if d.total_pages <> invalid then m.total = d.total_pages
                list = []
                for each it in d.results
                    if it.media_type = invalid or it.media_type <> "person" then list.push(ItemNode(it, m.gmt))
                end for
                m.gridRoot.appendChildren(list)
                if m.gridRoot.getChildCount() = 0 then m.msg.text = "No results found." else m.msg.text = ""
            end if
        end if
    end for
end sub

sub onApiError()
    m.loading = false
    m.msg.text = m.task.error
end sub

sub onGridFocus()
    if m.loading or m.page >= m.total then return
    if m.grid.itemFocused >= m.gridRoot.getChildCount() - 6 then
        m.page++
        loadPage()
    end if
end sub

sub onSelected()
    n = m.gridRoot.getChild(m.grid.itemSelected)
    if n <> invalid then m.top.request = MakeReq({ type: "title", mt: n.mt, id: n.tid })
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.grid.hasFocus() and key = "left" and (m.grid.itemFocused mod 4) = 0 then
        focusMe()
        return true
    else if key = "right" and not m.grid.hasFocus() and m.gridRoot.getChildCount() > 0 then
        m.grid.setFocus(true)
        return true
    else if key = "options" and m.top.mode = "genre" then
        m.gmt = iif(m.gmt = "movie", "tv", "movie")
        resetGrid("")
        loadGenres()
        return true
    end if
    return false
end function

sub focusMe()
    if m.top.mode = "search" then m.kb.setFocus(true) else m.glist.setFocus(true)
end sub

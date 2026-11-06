sub init()
    m.rows = m.top.findNode("rows")
    m.msg = m.top.findNode("msg")
    m.root = CreateObject("roSGNode", "ContentNode")
    m.rows.content = m.root
    m.rows.observeField("rowItemFocused", "onFocused")
    m.rows.observeField("rowItemSelected", "onSelected")
    m.defs = {}
    m.handled = {}
end sub

function Sections(mode as string) as object
    mv = "movie"
    tv = "tv"
    a = { t: "Trending Movies", e: "/trending/movie/week", mt: mv }
    b = { t: "Popular Movies", e: "/movie/popular", mt: mv }
    c = { t: "Top Rated Movies", e: "/movie/top_rated", mt: mv }
    d = { t: "Upcoming Movies", e: "/movie/upcoming", mt: mv }
    e = { t: "Now Playing", e: "/movie/now_playing", mt: mv }
    f = { t: "Trending TV Shows", e: "/trending/tv/week", mt: tv }
    g = { t: "Popular TV Shows", e: "/tv/popular", mt: tv }
    h = { t: "Top Rated TV Shows", e: "/tv/top_rated", mt: tv }
    i = { t: "Currently Airing TV Shows", e: "/tv/on_the_air", mt: tv }
    if mode = "movies" then return [a, b, c, d, e]
    if mode = "tv" then return [f, g, h, i]
    return [a, b, c, d, f, g, h, i]
end function

sub onMode()
    if m.top.mode = "favorites" then
        refresh()
        return
    end if
    reqs = []
    k = 0
    for each s in Sections(m.top.mode)
        row = m.root.createChild("ContentNode")
        row.title = s.t
        key = "r" + k.ToStr()
        m.defs[key] = { row: row, mt: s.mt }
        reqs.push({ key: key, endpoint: s.e })
        k++
    end for
    StartBatch(reqs)
end sub

sub refresh()
    if m.top.mode <> "favorites" then return
    m.root.removeChildrenIndex(m.root.getChildCount(), 0)
    total = 0
    for each pair in [["movie", "Favorite Movies"], ["tv", "Favorite TV Shows"]]
        list = []
        for each f in FavList(pair[0])
            list.push(FavNode(f))
        end for
        if list.count() > 0 then
            row = m.root.createChild("ContentNode")
            row.title = pair[1]
            row.appendChildren(list)
            total += list.count()
        end if
    end for
    if total = 0 then m.msg.text = "No favorites yet. Open a title and press * (options) to add it." else m.msg.text = ""
end sub

sub onResults()
    res = m.task.results
    for each key in res
        if not m.handled.doesExist(key) then
            m.handled[key] = true
            d = m.defs[key]
            if d <> invalid and res[key].results <> invalid then
                list = []
                for each it in res[key].results
                    list.push(ItemNode(it, d.mt))
                end for
                d.row.appendChildren(list)
                if key = "r0" and list.count() > 0 then showInfo(list[0])
            end if
        end if
    end for
end sub

sub onApiError()
    m.msg.text = m.task.error
end sub

sub showInfo(n as object)
    m.top.findNode("bg").uri = n.bg
    m.top.findNode("ftitle").text = n.title
    m.top.findNode("fmeta").text = n.ShortDescriptionLine1
    m.top.findNode("fover").text = n.ov
end sub

function ItemAt(idx as object) as object
    row = m.root.getChild(idx[0])
    if row = invalid then return invalid
    return row.getChild(idx[1])
end function

sub onFocused()
    n = ItemAt(m.rows.rowItemFocused)
    if n <> invalid then showInfo(n)
end sub

sub onSelected()
    n = ItemAt(m.rows.rowItemSelected)
    if n <> invalid then m.top.request = MakeReq({ type: "title", mt: n.mt, id: n.tid })
end sub

sub focusMe()
    m.rows.setFocus(true)
end sub

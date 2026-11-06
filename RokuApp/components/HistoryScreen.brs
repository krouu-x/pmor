sub onTarget()
    items = HistoryList()
    c = CreateObject("roSGNode", "ContentNode")
    for each e in items
        pct = 0
        if e.dur > 0 then pct = Int(e.last * 100 / e.dur)
        dt = CreateObject("roDateTime")
        dt.FromSeconds(e.ts)
        dt.ToLocalTime()
        c.createChild("ContentNode").title = e.title + "   |   watched " + FormatTime(e.watched) + " of " + FormatTime(e.dur) + "  (reached " + pct.ToStr() + "%)   |   " + dt.AsDateStringNoParam()
    end for
    m.top.findNode("list").content = c
    if items.count() = 0 then m.top.findNode("msg").text = "Nothing watched yet."
end sub

sub focusMe()
    m.top.findNode("list").setFocus(true)
end sub
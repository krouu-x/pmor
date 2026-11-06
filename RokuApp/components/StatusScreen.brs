sub init()
    m.paths = ["/api/health", "/api/status", "/api/metrics", "/api/providers"]
    m.body = m.top.findNode("body")
    m.top.findNode("refresh").observeField("buttonSelected", "onRefresh")
end sub

sub onTarget()
    onRefresh()
end sub

sub onRefresh()
    if m.body.text = "" then m.body.text = "Checking " + GetConfig().serviceBaseUrl + " ..."
    StartService(m.paths, "onServiceResults")
end sub

sub onServiceResults(ev as object)
    res = ev.getData()
    txt = ""
    for each p in m.paths
        r = res[p]
        if r <> invalid then
            if r.ok then
                txt += p + "    OK    " + r.latencyMs.ToStr() + " ms" + chr(10) + Summarize(r.data)
            else
                txt += p + "    FAILED    " + r.error + chr(10)
            end if
            txt += chr(10)
        end if
    end for
    m.body.text = txt
end sub

sub focusMe()
    m.top.findNode("refresh").setFocus(true)
end sub

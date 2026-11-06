sub init()
    m.opts = m.top.findNode("opts")
    c = CreateObject("roSGNode", "ContentNode")
    c.createChild("ContentNode").title = "Clear metadata cache"
    c.createChild("ContentNode").title = "Clear all favorites"
    c.createChild("ContentNode").title = "Server status"
    c.createChild("ContentNode").title = "Server address"
    m.opts.content = c
    m.opts.observeField("itemSelected", "onSelected")
end sub

sub onSelected()
    if m.opts.itemSelected = 0 then
        ClearCache()
        m.top.findNode("status").text = "Cache cleared."
    else if m.opts.itemSelected = 2 then
        m.top.request = MakeReq({ type: "status" })
    else if m.opts.itemSelected = 3 then
        showServerDialog()
    else
        reg = CreateObject("roRegistrySection", "favorites")
        reg.Delete("movie")
        reg.Delete("tv")
        reg.Flush()
        m.top.findNode("status").text = "Favorites cleared."
    end if
end sub

sub focusMe()
    m.opts.setFocus(true)
end sub

sub showServerDialog()
    current = GetConfig().serviceBaseUrl
    d = CreateObject("roSGNode", "StandardKeyboardDialog")
    d.title = "Server address"
    d.message = ["Enter full URL (http:// or https://) or IP:port (defaults to http:// + 8787).", "Current: " + current]
    d.text = current
    d.buttons = ["Save", "Reset", "Cancel"]
    d.observeField("buttonSelected", "onServerDialog")
    m.dlg = d
    m.top.getScene().dialog = d
end sub

sub onServerDialog()
    b = m.dlg.buttonSelected
    status = m.top.findNode("status")
    if b = 0 then
        url = NormalizeServerUrl(m.dlg.text)
        if url <> "" then
            SaveServerUrl(url)
            status.text = "Server set to " + url
        end if
    else if b = 1 then
        SaveServerUrl("")
        status.text = "Server reset to " + GetConfig().serviceBaseUrl
    end if
    m.top.getScene().dialog = invalid
    m.opts.setFocus(true)
end sub
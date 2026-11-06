sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    host = "127.0.0.1"
    ips = CreateObject("roDeviceInfo").GetIPAddrs()
    for each k in ips
        host = ips[k]
        exit for
    end for
    x = CreateObject("roUrlTransfer")
    x.SetUrl("http://" + host + ":8060/launch/837?contentId=" + m.top.videoKey + "&mediaType=movie")
    code = x.PostFromString("")
    if code = 200 or code = 202 then
        m.top.status = "ok"
    else
        m.top.status = "Could not open YouTube (error " + code.ToStr() + "). Set Settings > System > Advanced > External control to Default."
    end if
end sub

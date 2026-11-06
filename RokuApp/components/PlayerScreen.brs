sub init()
    m.video = m.top.findNode("video")
    m.seekUI = m.top.findNode("seekUI")
    m.fill = m.top.findNode("fill")
    m.timeLbl = m.top.findNode("timeLbl")
    m.speedLbl = m.top.findNode("speedLbl")
    m.pauseLbl = m.top.findNode("pauseLbl")
    m.hideTimer = m.top.findNode("hideTimer")
    m.saveTimer = m.top.findNode("saveTimer")
    m.tick = m.top.findNode("tick")
    m.video.observeField("state", "onState")
    m.video.observeField("position", "onPosition")
    m.hideTimer.observeField("fire", "onHide")
    m.saveTimer.observeField("fire", "saveHistory")
    m.tick.observeField("fire", "onTick")
    m.holdClock = CreateObject("roTimespan")
    m.idleClock = CreateObject("roTimespan")
    m.commitClock = CreateObject("roTimespan")
    m.keyDown = false
    m.active = false
    m.committed = false
    m.dir = 0
    m.speed = 0
    m.target = 0.0
    m.watched = 0
    m.lastPos = -1
    m.title = ""
end sub

sub onTarget()
    t = m.top.target
    m.title = NodeText(t.title)
    prev = HistoryFind(m.title)
    if prev <> invalid then m.watched = prev.watched
    c = CreateObject("roSGNode", "ContentNode")
    c.url = t.url
    c.title = t.title
    c.streamFormat = "mp4"
    if Instr(1, LCase(t.url), ".m3u8") > 0 then c.streamFormat = "hls"
    u = LCase(t.url)
    q = Instr(1, u, "?")
    if q > 0 then u = Left(u, q - 1)
    if Right(u, 4) = ".mkv" then c.streamFormat = "mkv"
    m.video.content = c
    m.video.control = "play"
    m.saveTimer.control = "start"
    m.top.setFocus(true)
end sub

' ---------- watch tracking ----------
sub onPosition()
    cur = m.video.position
    if m.video.state = "playing" and m.lastPos >= 0 then
        d = cur - m.lastPos
        if d > 0 and d < 5 then m.watched += d
    end if
    m.lastPos = cur
end sub

sub saveHistory()
    if m.title = "" then return
    HistorySave({ title: m.title, watched: Int(m.watched), last: Int(m.video.position), dur: Int(m.video.duration), ts: CreateObject("roDateTime").AsSeconds() })
end sub

sub onState()
    st = m.video.state
    m.pauseLbl.visible = (st = "paused")
    if st = "playing" and not m.top.isInFocusChain() then m.top.setFocus(true)
    if st = "error" then m.top.findNode("msg").text = "Playback error: " + NodeText(m.video.errorMsg)
    if st = "finished" or st = "paused" then saveHistory()
end sub

' ---------- accelerating seek ----------
function SeekSpeed(held as integer) as integer
    t = held / 1000
    if t < 1.5 then return 30
    if t < 3 then return 60
    if t < 5 then return 120
    if t < 8 then return 240
    return 480
end function

function ClampSeek(v as float, dur as float) as float
    if v < 0 then return 0
    if dur > 0 then
        if v > dur - 2 then return dur - 2
    end if
    return v
end function

' Taps keep building on our own target until the player has caught up with the last seek.
function BaseTime() as float
    if m.committed then
        if m.commitClock.TotalMilliseconds() < 3000 then return m.target
    end if
    return m.video.position
end function

sub showSeekUI()
    dur = m.video.duration
    if dur > 0 then m.fill.width = 1600 * m.target / dur
    m.timeLbl.text = FormatTime(m.target) + " / " + FormatTime(dur)
    if m.speed > 0 then m.speedLbl.text = m.speed.ToStr() + "x" else m.speedLbl.text = ""
    m.seekUI.visible = true
    m.hideTimer.control = "stop"
end sub

sub beginKey(dir as integer)
    m.idleClock.Mark()
    if m.keyDown and m.dir = dir then return
    if not m.active then
        m.target = BaseTime()
        m.active = true
        m.tick.control = "start"
    end if
    m.keyDown = true
    m.dir = dir
    m.holdClock.Mark()
    m.speed = 0
    m.target = ClampSeek(m.target + dir * 10, m.video.duration)
    showSeekUI()
end sub

sub onTick()
    if not m.active then
        m.tick.control = "stop"
        return
    end if
    idle = m.idleClock.TotalMilliseconds()
    if m.keyDown then
        held = m.holdClock.TotalMilliseconds()
        if idle > 5000 then
            m.keyDown = false
        else if held > 400 then
            m.speed = SeekSpeed(held)
            m.target = ClampSeek(m.target + m.dir * m.speed * 0.1, m.video.duration)
        end if
        showSeekUI()
    else if idle >= 350 then
        commitSeek()
    end if
end sub

sub commitSeek()
    m.active = false
    m.dir = 0
    m.speed = 0
    m.tick.control = "stop"
    m.video.seek = m.target
    m.lastPos = -1
    m.committed = true
    m.commitClock.Mark()
    showSeekUI()
    m.hideTimer.control = "start"
end sub

sub onHide()
    m.seekUI.visible = false
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    print "KEY:"; key; " press="; press
    if key = "right" or key = "left" then
        if press then
            dir = 1
            if key = "left" then dir = -1
            beginKey(dir)
            m.idleClock.Mark()
        else
            m.keyDown = false
            m.idleClock.Mark()
        end if
        return true
    else if key = "OK" or key = "play" then
        if press then
            if m.video.state = "paused" then
                m.video.control = "resume"
            else if m.video.state = "playing" then
                m.video.control = "pause"
            end if
        end if
        return true
    end if
    return false
end function

sub stopPlayback()
    saveHistory()
    m.saveTimer.control = "stop"
    m.tick.control = "stop"
    m.video.control = "stop"
end sub

sub focusMe()
    m.top.setFocus(true)
end sub
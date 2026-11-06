sub init()
    m.streamGrid = m.top.findNode("streamGrid")
    m.audioGrid = m.top.findNode("audioGrid")
    m.subtitleGrid = m.top.findNode("subtitleGrid")
    m.playBtn = m.top.findNode("playBtn")
    m.cancelBtn = m.top.findNode("cancelBtn")

    m.streamGrid.observeField("itemSelected", "onStreamSelected")
    m.audioGrid.observeField("itemSelected", "onAudioSelected")
    m.subtitleGrid.observeField("itemSelected", "onSubtitleSelected")
    m.playBtn.observeField("buttonSelected", "onPlay")
    m.cancelBtn.observeField("buttonSelected", "onCancel")

    m.selectedStreamIndex = 0
    m.selectedAudioIndex = 0
    m.selectedSubtitleIndex = -1  ' -1 means off
end sub

sub onTarget()
    t = m.top.target
    m.streams = t.streams
    m.onPlayCallback = t.onPlay
    m.title = t.title

    ' Populate streams grid
    populateStreams()

    ' For now, select first stream and populate audio/subtitle from it
    if m.streams.count() > 0 then
        onStreamSelectedInternal(0)
    end if
end sub

sub populateStreams()
    c = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.streams.count() - 1
        s = m.streams[i]
        item = c.createChild("ContentNode")
        ' Build stream label: quality + codec + size + provider
        label = ""
        if s.quality <> invalid then label += s.quality
        if s.codec <> invalid then
            if label <> "" then label += " • "
            label += UCase(s.codec)
        end if
        if s.size <> invalid then
            if label <> "" then label += " • "
            label += formatSize(s.size)
        end if
        if s.provider <> invalid then
            if label <> "" then label += " • "
            label += s.provider
        end if
        if s.languages <> invalid and s.languages.count() > 0 then
            if label <> "" then label += " • "
            label += "Audio: " + JoinNames(s.languages)
        end if
        if s.subtitles <> invalid and s.subtitles.count() > 0 then
            if label <> "" then label += " • "
            label += "Subs: " + JoinNames(s.subtitles)
        end if
        if label = "" then label = "Stream " + (i+1).ToStr()
        item.title = label
        item.streamIndex = i
    end for
    m.streamGrid.content = c
end sub

sub onStreamSelected()
    i = m.streamGrid.itemSelected
    onStreamSelectedInternal(i)
end sub

sub onStreamSelectedInternal(i as integer)
    m.selectedStreamIndex = i
    if i < 0 or i >= m.streams.count() then return

    stream = m.streams[i]
    populateAudio(stream)
    populateSubtitles(stream)
end sub

sub populateAudio(stream as object)
    c = CreateObject("roSGNode", "ContentNode")
    ' Add "Auto" option first
    item = c.createChild("ContentNode")
    item.title = "Auto (Default)"
    item.trackIndex = -1

    if stream.audioTracks <> invalid then
        for j = 0 to stream.audioTracks.count() - 1
            track = stream.audioTracks[j]
            item = c.createChild("ContentNode")
            label = track.language
            if track.codec <> invalid then label += " (" + track.codec + ")"
            if track.channels <> invalid then label += " " + track.channels.ToStr() + "ch"
            item.title = label
            item.trackIndex = j
        end for
    else if stream.languages <> invalid then
        ' Fallback: use languages array
        for j = 0 to stream.languages.count() - 1
            item = c.createChild("ContentNode")
            item.title = stream.languages[j]
            item.trackIndex = j
        end for
    end if

    m.audioGrid.content = c
    m.selectedAudioIndex = 0
end sub

sub populateSubtitles(stream as object)
    c = CreateObject("roSGNode", "ContentNode")
    ' Add "Off" option first
    item = c.createChild("ContentNode")
    item.title = "Off"
    item.trackIndex = -1

    if stream.subtitleTracks <> invalid then
        for j = 0 to stream.subtitleTracks.count() - 1
            track = stream.subtitleTracks[j]
            item = c.createChild("ContentNode")
            label = track.language
            if track.forced = true then label += " (Forced)"
            if track.sdh = true then label += " (SDH)"
            item.title = label
            item.trackIndex = j
        end for
    else if stream.subtitles <> invalid then
        ' Fallback: use subtitles array
        for j = 0 to stream.subtitles.count() - 1
            item = c.createChild("ContentNode")
            item.title = stream.subtitles[j]
            item.trackIndex = j
        end for
    end if

    m.subtitleGrid.content = c
    m.selectedSubtitleIndex = -1
end sub

sub onAudioSelected()
    m.selectedAudioIndex = m.audioGrid.itemSelected
end sub

sub onSubtitleSelected()
    m.selectedSubtitleIndex = m.subtitleGrid.itemSelected
end sub

sub onPlay()
    if m.selectedStreamIndex < 0 or m.selectedStreamIndex >= m.streams.count() then return

    stream = m.streams[m.selectedStreamIndex]
    audioTrack = invalid
    subtitleTrack = invalid

    ' Get selected audio track index
    audioContent = m.audioGrid.content
    if audioContent <> invalid and m.selectedAudioIndex >= 0 and m.selectedAudioIndex < audioContent.getChildCount() then
        audioItem = audioContent.getChild(m.selectedAudioIndex)
        if audioItem.trackIndex <> invalid and audioItem.trackIndex >= 0 then
            audioTrack = audioItem.trackIndex
        end if
    end if

    ' Get selected subtitle track index
    subtitleContent = m.subtitleGrid.content
    if subtitleContent <> invalid and m.selectedSubtitleIndex >= 0 and m.selectedSubtitleIndex < subtitleContent.getChildCount() then
        subtitleItem = subtitleContent.getChild(m.selectedSubtitleIndex)
        if subtitleItem.trackIndex <> invalid and subtitleItem.trackIndex >= 0 then
            subtitleTrack = subtitleItem.trackIndex
        end if
    end if

    ' Send play request to parent via request field
    m.top.request = MakeReq({ type: "play", stream: stream, audioTrack: audioTrack, subtitleTrack: subtitleTrack })
end sub

sub onCancel()
    m.top.request = MakeReq({ type: "close" })
end sub

sub focusMe()
    m.streamGrid.setFocus(true)
end sub

function formatSize(bytes as dynamic) as string
    if bytes = invalid then return ""
    b = bytes
    if b >= 1073741824 then return (b / 1073741824.0).ToStr() + " GB"
    if b >= 1048576 then return (b / 1048576.0).ToStr() + " MB"
    if b >= 1024 then return (b / 1024.0).ToStr() + " KB"
    return b.ToStr() + " B"
end function
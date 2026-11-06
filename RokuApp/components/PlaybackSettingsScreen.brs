sub init()
    m.audioList = m.top.findNode("audioList")
    m.subtitleList = m.top.findNode("subtitleList")
    m.audioContent = m.top.findNode("audioContent")
    m.subtitleContent = m.top.findNode("subtitleContent")
    m.applyBtn = m.top.findNode("applyBtn")
    m.cancelBtn = m.top.findNode("cancelBtn")
    m.titleLabel = m.top.findNode("titleLabel")

    m.audioList.observeField("itemSelected", "onAudioSelected")
    m.subtitleList.observeField("itemSelected", "onSubtitleSelected")
    m.applyBtn.observeField("buttonSelected", "onApply")
    m.cancelBtn.observeField("buttonSelected", "onCancel")

    m.selectedAudioIndex = 0
    m.selectedSubtitleIndex = 0
end sub

sub onTarget()
    t = m.top.target
    m.stream = t.stream
    m.onApplyCallback = t.onApply

    ' Set current selections
    m.currentAudioTrack = t.currentAudioTrack
    m.currentSubtitleTrack = t.currentSubtitleTrack

    ' Populate audio tracks
    populateAudio()

    ' Populate subtitle tracks
    populateSubtitles()

    ' Set initial focus
    m.audioList.setFocus(true)
end sub

sub populateAudio()
    c = CreateObject("roSGNode", "ContentNode")

    ' Add "Auto" option first
    item = c.createChild("ContentNode")
    item.title = "Auto (Default)"
    item.trackIndex = -1

    tracks = m.stream.audioTracks
    if tracks <> invalid then
        for j = 0 to tracks.count() - 1
            track = tracks[j]
            item = c.createChild("ContentNode")
            label = track.language
            if track.codec <> invalid then label += " (" + track.codec + ")"
            if track.channels <> invalid then label += " " + track.channels.ToStr() + "ch"
            item.title = label
            item.trackIndex = j
        end for
    end if

    m.audioContent = c
    m.audioList.content = c

    ' Select current audio track
    if m.currentAudioTrack <> invalid and m.currentAudioTrack >= 0 then
        m.selectedAudioIndex = m.currentAudioTrack + 1  ' +1 for "Auto" option
    else
        m.selectedAudioIndex = 0
    end if
    m.audioList.jumpToItem(m.selectedAudioIndex)
end sub

sub populateSubtitles()
    c = CreateObject("roSGNode", "ContentNode")

    ' Add "Off" option first
    item = c.createChild("ContentNode")
    item.title = "Off"
    item.trackIndex = -1

    tracks = m.stream.subtitleTracks
    if tracks <> invalid then
        for j = 0 to tracks.count() - 1
            track = tracks[j]
            item = c.createChild("ContentNode")
            label = track.language
            if track.forced = true then label += " (Forced)"
            if track.sdh = true then label += " (SDH)"
            item.title = label
            item.trackIndex = j
        end for
    end if

    m.subtitleContent = c
    m.subtitleList.content = c

    ' Select current subtitle track
    if m.currentSubtitleTrack <> invalid and m.currentSubtitleTrack >= 0 then
        m.selectedSubtitleIndex = m.currentSubtitleTrack + 1  ' +1 for "Off" option
    else
        m.selectedSubtitleIndex = 0
    end if
    m.subtitleList.jumpToItem(m.selectedSubtitleIndex)
end sub

sub onAudioSelected()
    m.selectedAudioIndex = m.audioList.itemSelected
end sub

sub onSubtitleSelected()
    m.selectedSubtitleIndex = m.subtitleList.itemSelected
end sub

sub onApply()
    ' Get selected audio track index
    audioTrack = invalid
    if m.selectedAudioIndex >= 0 and m.selectedAudioIndex < m.audioContent.getChildCount() then
        audioItem = m.audioContent.getChild(m.selectedAudioIndex)
        if audioItem.trackIndex <> invalid then
            audioTrack = audioItem.trackIndex
        end if
    end if

    ' Get selected subtitle track index
    subtitleTrack = invalid
    if m.selectedSubtitleIndex >= 0 and m.selectedSubtitleIndex < m.subtitleContent.getChildCount() then
        subtitleItem = m.subtitleContent.getChild(m.selectedSubtitleIndex)
        if subtitleItem.trackIndex <> invalid then
            subtitleTrack = subtitleItem.trackIndex
        end if
    end if

    ' Send result back to PlayerScreen
    m.top.request = MakeReq({
        type: "play",
        audioTrack: audioTrack,
        subtitleTrack: subtitleTrack
    })
end sub

sub onCancel()
    m.top.request = MakeReq({ type: "close" })
end sub

sub focusMe()
    m.audioList.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back" then
        onCancel()
        return true
    end if
    return false
end function
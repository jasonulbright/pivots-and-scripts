# Contrast violations that exist today and are not fixed yet. Each entry is
# "<control>:<metric>" or "text:<visible text>". The window test fails when a
# violation is not listed (a new defect) and when a listed one no longer happens
# (remove it here). Run Show-ContrastViolations.ps1 to print the current list.
#
# Text must reach 4.5:1 and a control border 3:1, enabled and disabled, in both
# themes. The causes are shared by every suite tool: the SuiteCommon palette
# (sidebar button border #555555 on #1E1E1E is 2.06:1), the MahApps disabled
# style, the light text box border and the unselected tab header. The fix
# belongs in app-packager-suite, then a sync of the vendored copy, not here.
function Get-KnownContrastDefect {
    param([Parameter(Mandatory)][ValidateSet('dark', 'light')][string]$Theme)
    switch ($Theme) {
        'dark' {
            @(
                'btnCheck:DisabledText', 'btnConnect:DisabledText', 'btnCopy:DisabledText',
                'btnCsv:DisabledText', 'btnFind:DisabledText', 'btnGrid:DisabledText',
                'btnHistory:DisabledBorder', 'btnHistory:EnabledBorder', 'btnImport:DisabledText',
                'btnJson:DisabledText', 'btnNewSession:DisabledText', 'btnOpen:DisabledText',
                'btnOptions:DisabledBorder', 'btnOptions:EnabledBorder', 'btnParameters:DisabledText',
                'btnPivot:DisabledBorder', 'btnPivot:DisabledText', 'btnPivot:EnabledBorder',
                'btnReplace:DisabledText', 'btnResolve:DisabledText', 'btnRun:DisabledText',
                'btnSave:DisabledText', 'btnSaveSession:DisabledText', 'btnScript:DisabledBorder',
                'btnScript:DisabledText', 'btnScript:EnabledBorder', 'btnSelectionPivot:DisabledText',
                'btnSelectionScript:DisabledText', 'btnSiteScripts:DisabledText', 'btnStop:DisabledText',
                'btnSubmit:DisabledText', 'btnTargets:DisabledText', 'text:Results',
                'text:Stop waiting', 'titlebar:inactive'
            )
        }
        'light' {
            @(
                'btnCheck:DisabledText', 'btnConnect:DisabledText', 'btnCopy:DisabledText',
                'btnCsv:DisabledText', 'btnFind:DisabledText', 'btnGrid:DisabledText',
                'btnHistory:DisabledText', 'btnImport:DisabledText', 'btnJson:DisabledText',
                'btnNewSession:DisabledText', 'btnOpen:DisabledText', 'btnOptions:DisabledText',
                'btnParameters:DisabledText', 'btnPivot:DisabledText', 'btnReplace:DisabledText',
                'btnResolve:DisabledText', 'btnRun:DisabledText', 'btnSave:DisabledText',
                'btnSaveSession:DisabledText', 'btnScript:DisabledText', 'btnSelectionPivot:DisabledText',
                'btnSelectionScript:DisabledText', 'btnSiteScripts:DisabledText', 'btnStop:DisabledText',
                'btnSubmit:DisabledText', 'btnTargets:DisabledText', 'findText:DisabledBorder',
                'findText:EnabledBorder', 'libraryFilter:DisabledBorder', 'libraryFilter:EnabledBorder',
                'replaceText:DisabledBorder', 'replaceText:EnabledBorder', 'resultFilter:DisabledBorder',
                'resultFilter:EnabledBorder', 'scriptGuid:DisabledBorder', 'scriptGuid:EnabledBorder',
                'targetInput:DisabledBorder', 'targetInput:EnabledBorder', 'targetKind:DisabledBorder',
                'targetKind:DisabledText', 'targetKind:EnabledBorder', 'targetKind:EnabledText',
                'text:Devices', 'text:Pipeline', 'text:Raw',
                'text:Stop waiting', 'titlebar:inactive'
            )
        }
    }
}

function Test-LargeText {
    # WCAG large text: 24 px, or 18.66 px and bold. It needs 3:1; other text needs 4.5:1.
    param([Parameter(Mandatory)]$Row)
    return ($Row.Size -ge 24 -or ($Row.Bold -and $Row.Size -ge 18.66))
}

function Get-ContrastViolationKey {
    # The one place that decides what a contrast violation is and how it is named. The window
    # test and Show-ContrastViolations.ps1 both call it, so the printed list always matches
    # what the test expects. $Views are measured views (Text, Interactive and TitleBar).
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Views)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($v in $Views) {
        foreach ($r in $v.Text) {
            $min = if (Test-LargeText $r) { 3.0 } else { 4.5 }
            if ($r.Ratio -lt $min) { [void]$keys.Add(('text:{0}' -f $r.Text)) }
        }
        foreach ($c in $v.Interactive) {
            foreach ($metric in 'EnabledText', 'DisabledText', 'EnabledBorder', 'DisabledBorder') {
                $value = $c.$metric
                if ($null -eq $value) { continue }
                $min = if ($metric -like '*Text') { 4.5 } else { 3.0 }
                if ($value -lt $min) { [void]$keys.Add(('{0}:{1}' -f $c.Name, $metric)) }
            }
        }
    }
    $inactive = @($Views)[0].TitleBar.Inactive
    if ($null -ne $inactive -and $inactive -lt 4.5) { [void]$keys.Add('titlebar:inactive') }
    return @($keys | Sort-Object -Unique)
}
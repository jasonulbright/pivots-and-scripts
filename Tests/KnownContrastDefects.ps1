# Contrast violations that exist today and are not fixed yet. Each entry is
# "<control>:<metric>" or "text:<visible text>". The window test fails when a
# violation is not listed (a new defect) and when a listed one no longer happens
# (remove it here). Run Show-ContrastViolations.ps1 to print the current list.
#
# Text must reach 4.5:1 and a control border 3:1 when the control is enabled, in both
# themes. A disabled control is exempt (WCAG 1.4.3 exempts inactive components) and must look dimmed.
# Accepted limit: SuiteCommon sets a local Foreground, Background and BorderBrush on the four sidebar buttons. A local value beats
# the disabled trigger of the button style, so their disabled state is what SuiteCommon paints. The fix belongs in app-packager-suite.
# One defect remains, in the light theme:
#   - targetKind:EnabledText. The MahApps combo box draws its drop-down arrow glyph in a content
#     presenter with Opacity 0.5. The measure reads the glyph as text: black at half opacity on white is 3.95:1 (a graphic
#     needs 3:1). The glyph is part of the MahApps template; the dark theme passes.
function Get-KnownContrastDefect {
    param([Parameter(Mandatory)][ValidateSet('dark', 'light')][string]$Theme)
    switch ($Theme) {
        'dark' { @() }
        'light' { @('targetKind:EnabledText') }
    }
}

function Get-HexLuminance {
    # WCAG relative luminance of a color text such as #FFRRGGBB (the alpha byte is ignored).
    param([Parameter(Mandatory)][string]$Hex)
    $h = $Hex.TrimStart('#'); if ($h.Length -eq 8) { $h = $h.Substring(2) }
    $f = { param($v) $v = $v / 255.0; if ($v -le 0.04045) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) } }
    $r = [Convert]::ToInt32($h.Substring(0, 2), 16); $g = [Convert]::ToInt32($h.Substring(2, 2), 16); $bl = [Convert]::ToInt32($h.Substring(4, 2), 16)
    return (0.2126 * (& $f $r) + 0.7152 * (& $f $g) + 0.0722 * (& $f $bl))
}

function Get-DimmedControlViolation {
    # A disabled control must be clearly dimmed (enabled text / disabled text >= 1.25) and still readable (disabled text >= 1.5).
    # WCAG 1.4.3 exempts disabled components from 4.5:1, so no higher target applies. A control that drops its fill to the surface
    # of the window when disabled (a blue sidebar button turns white with gray text) also reads as disabled: its fill then differs
    # from the enabled fill by 1.25 or more. Returns one text per offender.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Views)
    foreach ($v in $Views) {
        foreach ($c in $v.Interactive) {
            if ($null -eq $c.EnabledText -or $null -eq $c.DisabledText) { continue }
            $step = $c.EnabledText / [math]::Max($c.DisabledText, 0.01)
            $fillChanged = $false
            if ($c.EnabledBackdrop -and $c.DisabledBackdrop -and $c.EnabledBackdrop -ne $c.DisabledBackdrop) {
                $le = Get-HexLuminance $c.EnabledBackdrop; $ld = Get-HexLuminance $c.DisabledBackdrop
                $fillChanged = ((([math]::Max($le, $ld) + 0.05) / ([math]::Min($le, $ld) + 0.05)) -ge 1.25)
            }
            if ($fillChanged) { if ($c.DisabledText -lt 1.5) { '{0}: disabled text {1}, not readable (needs 1.5)' -f $c.Name, $c.DisabledText } }
            elseif ($step -lt 1.25) { '{0}: enabled {1} / disabled {2} = {3:N2}, not dimmed (needs 1.25)' -f $c.Name, $c.EnabledText, $c.DisabledText, $step }
            elseif ($c.DisabledText -lt 1.5) { '{0}: disabled text {1}, not readable (needs 1.5)' -f $c.Name, $c.DisabledText }
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
            # A disabled control is exempt from the text and border rules (WCAG 1.4.3 exempts inactive components). It must look
            # dimmed instead: see Get-DimmedControlViolation. Only the enabled metrics count here.
            foreach ($metric in 'EnabledText', 'EnabledBorder') {
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

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class HubPickerNative {
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint command);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder name, int capacity);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint message, IntPtr wparam, IntPtr lparam);
    public static string Class(IntPtr h) { var s = new StringBuilder(256); GetClassNameW(h, s, s.Capacity); return s.ToString(); }
}
'@

function Assert-PickerNode($Session, [IntPtr]$Handle, [string]$Class, [int]$Id, [IntPtr]$Parent) {
    $ownerPid = [uint32]0
    $null = [VerifyWindow]::GetWindowThreadProcessId($Handle, [ref]$ownerPid)
    Assert-That ($Handle -ne [IntPtr]::Zero -and [VerifyPasteImage]::IsWindow($Handle) -and $ownerPid -eq $Session.pid -and [HubPickerNative]::Class($Handle) -ceq $Class) "picker: invalid owned $Class"
    if ($Id -ge 0) { Assert-That ([HubPickerNative]::GetDlgCtrlID($Handle) -eq $Id -and [HubPickerNative]::GetParent($Handle) -eq $Parent) "picker: invalid parent or id for $Class" }
}

function Assert-PickerTree($Session, $Tree) {
    $null = Get-App $Session
    Assert-PickerNode $Session $Tree.main 'MessagesZig' -1 ([IntPtr]::Zero)
    Assert-PickerNode $Session $Tree.dialog '#32770' -1 ([IntPtr]::Zero)
    Assert-That ([HubPickerNative]::GetWindow($Tree.dialog, 4) -eq $Tree.main -and [VerifyPasteImage]::IsWindowVisible($Tree.dialog)) 'picker: dialog owner changed'
    Assert-PickerNode $Session $Tree.top 'ComboBoxEx32' 1148 $Tree.dialog
    Assert-PickerNode $Session $Tree.combo 'ComboBox' 1148 $Tree.top
    Assert-PickerNode $Session $Tree.edit 'Edit' 1148 $Tree.combo
    Assert-PickerNode $Session $Tree.open 'Button' 1 $Tree.dialog
}

function Save-PickerRead($Session, $Tree, [string]$Phase) {
    foreach ($name in @('top', 'combo', 'edit')) {
        Assert-PickerTree $Session $Tree
        $handle = $Tree[$name]
        $buffer = [Text.StringBuilder]::new(32768)
        $result = [UIntPtr]::Zero
        $ok = [VerifyWindow]::ReadText($handle, 13, [UIntPtr]32768, $buffer, 2, 2000, [ref]$result)
        $row = @{ phase = $Phase; name = $name; hwnd = $handle.ToInt64(); class = [HubPickerNative]::Class($handle); id = [HubPickerNative]::GetDlgCtrlID($handle); parent = [HubPickerNative]::GetParent($handle).ToInt64(); ok = $ok.ToInt64(); result = $result.ToUInt64(); text = $buffer.ToString() }
        $row | ConvertTo-Json -Compress | Add-Content (Join-Path $Session.evidence 'picker-native.jsonl')
        if ($name -eq 'edit') { $editText = $buffer.ToString(); $editOk = $ok }
    }
    Assert-That ($editOk -ne [IntPtr]::Zero) 'picker: edit read timed out'
    return $editText
}

function Add-HubPickerImage($Session, [string]$Path) {
    $main = [IntPtr](Get-Window $Session).Current.NativeWindowHandle
    $attach = [VerifyWindow]::GetDlgItem($main, 1136)
    Assert-PickerNode $Session $main 'MessagesZig' -1 ([IntPtr]::Zero)
    Assert-PickerNode $Session $attach 'Button' 1136 $main
    Assert-That ([HubPickerNative]::PostMessageW($main, 0x111, [IntPtr]1136, $attach)) 'picker: attach command post failed'
    $dialog = Wait-Until {
        $dialogs = @([VerifyPasteImage]::Dialogs($Session.pid))
        if ($dialogs.Count -gt 1) { throw 'picker: multiple owned dialogs' }
        if ($dialogs.Count -eq 1) { $dialogs[0] }
    } 'owned native file dialog'
    $top = [VerifyWindow]::GetDlgItem($dialog, 1148)
    $combo = [VerifyWindow]::GetDlgItem($top, 1148)
    $edit = [VerifyWindow]::GetDlgItem($combo, 1148)
    $open = [VerifyWindow]::GetDlgItem($dialog, 1)
    $tree = @{ main = $main; dialog = $dialog; top = $top; combo = $combo; edit = $edit; open = $open }
    foreach ($name in @('main', 'dialog', 'top', 'combo', 'edit', 'open')) {
        $h = $tree[$name]
        @{ phase = 'hierarchy'; name = $name; hwnd = $h.ToInt64(); class = [HubPickerNative]::Class($h); id = [HubPickerNative]::GetDlgCtrlID($h); parent = [HubPickerNative]::GetParent($h).ToInt64(); owner = [HubPickerNative]::GetWindow($h, 4).ToInt64() } | ConvertTo-Json -Compress | Add-Content (Join-Path $Session.evidence 'picker-native.jsonl')
    }
    Assert-PickerTree $Session $tree
    $null = Save-PickerRead $Session $tree 'before'
    Assert-PickerTree $Session $tree
    $result = [UIntPtr]::Zero
    $ok = [VerifyWindow]::WriteText($edit, 12, [UIntPtr]::Zero, $Path, 2, 2000, [ref]$result)
    @{ phase = 'set-edit'; ok = $ok.ToInt64(); result = $result.ToUInt64(); input = $Path } | ConvertTo-Json -Compress | Add-Content (Join-Path $Session.evidence 'picker-native.jsonl')
    $actual = Save-PickerRead $Session $tree 'after-edit'
    Assert-That ($ok -ne [IntPtr]::Zero -and $result.ToUInt64() -ne 0) 'picker: edit WM_SETTEXT failed'
    if ($actual -cne $Path) {
        Assert-PickerTree $Session $tree
        $result = [UIntPtr]::Zero
        $ok = [VerifyWindow]::WriteText($combo, 12, [UIntPtr]::Zero, $Path, 2, 2000, [ref]$result)
        @{ phase = 'set-combo'; ok = $ok.ToInt64(); result = $result.ToUInt64(); input = $Path } | ConvertTo-Json -Compress | Add-Content (Join-Path $Session.evidence 'picker-native.jsonl')
        $actual = Save-PickerRead $Session $tree 'after-combo'
        Assert-That ($ok -ne [IntPtr]::Zero -and $result.ToUInt64() -ne 0) 'picker: combo WM_SETTEXT failed'
    }
    Assert-That ($actual -ceq $Path) 'picker: canonical edit differs from fixture path'
    Assert-PickerTree $Session $tree
    $caption = [Text.StringBuilder]::new(256)
    $length = [UIntPtr]::Zero
    $captionOk = [VerifyWindow]::ReadText($open, 13, [UIntPtr]256, $caption, 2, 2000, [ref]$length)
    @{ phase = 'open-caption'; ok = $captionOk.ToInt64(); result = $length.ToUInt64(); text = $caption.ToString() } | ConvertTo-Json -Compress | Add-Content (Join-Path $Session.evidence 'picker-native.jsonl')
    Assert-That ($captionOk -ne [IntPtr]::Zero -and $caption.ToString() -ceq '&Open' -and [VerifyWindow]::IsWindowEnabled($open)) 'picker: unexpected Open button'
    Assert-PickerTree $Session $tree
    Assert-That ([HubPickerNative]::PostMessageW($open, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)) 'picker: Open click post failed'
    Add-Content (Join-Path $Session.evidence 'picker-native.jsonl') '{"phase":"open-posted"}'
    $null = Wait-Until { -not [VerifyPasteImage]::IsWindow($dialog) } 'native picker closed'
}

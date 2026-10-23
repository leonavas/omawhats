import QtQuick

// A line of plain text to type in: the search, the phone number, the
// profile's edits. A TextEdit, not a TextInput: a writable TextInput reads
// in full whatever text any app puts on the clipboard, as soon as it's put
// there (to know whether it could paste), so a huge or stalled offer would
// hang the shell; a TextEdit only looks at the kinds offered, and reads the
// text on a paste. Lines pasted in become one; maximumLength as TextInput's.
TextEdit {
  id: le
  property int maximumLength: -1
  textFormat: TextEdit.PlainText
  wrapMode: TextEdit.NoWrap
  onTextChanged: {
    var s = le.text.replace(/\t/g, "").replace(/[\r\n\u2028\u2029]+/g, " ")
    if (le.maximumLength >= 0 && s.length > le.maximumLength) s = s.slice(0, le.maximumLength)
    if (s === le.text) return
    var c = Math.min(le.cursorPosition, s.length)
    le.text = s
    le.cursorPosition = c
  }
}

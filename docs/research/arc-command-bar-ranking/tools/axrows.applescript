-- prints the static texts inside Arc's front window (command bar rows), one per line, depth-first
on run argv
  set out to ""
  tell application "System Events" to tell process "Arc"
    set w to front window
    try
      set es to entire contents of w
      repeat with e in es
        try
          set r to role of e
          if r is "AXStaticText" or r is "AXTextField" or r is "AXRow" or r is "AXCell" then
            set v to ""
            try
              set v to value of e as text
            end try
            set d to ""
            try
              set d to description of e as text
            end try
            set out to out & r & " | " & v & " | " & d & linefeed
          end if
        end try
      end repeat
    end try
  end tell
  return out
end run

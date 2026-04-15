on run argv
	-- Select a reasonable time for the script to finish in seconds (i.e. 30*60 minutes)
	set scriptTimeout to 30 * 60
	set curDate to do shell script "date +'%Y%m%d'"
	set zipname to "/Users/Jason/Dropbox/xfer/evernote-" & curDate & ".tar.gz"

	tell application "System Events"
		set exportPath to home directory of current user & "/Desktop/"
	end tell

	-- Create the folder type directory if needed
	set exportPath to exportPath & "/"
	set quotedExportPath to "'" & exportPath & "'"
	do shell script "if [ ! -e " & quoted form of exportPath & " ]; then mkdir " & quoted form of exportPath & "; fi;"

	-- Create the folder date directory if needed
	set exportPath to exportPath & "Evernote-" & curDate & "/"
	set quotedExportPath to "'" & exportPath & "'"
	do shell script "if [ ! -e " & quoted form of exportPath & " ]; then mkdir " & quoted form of exportPath & "; fi;"

	with timeout of (scriptTimeout) seconds
		tell application "Evernote"

			-- For every notebook...
			repeat with currentNotebook in every notebook of application "Evernote"
				set notebookName to the name of currentNotebook

				-- TODO organize by stack
				set matches to every note in notebook notebookName

				set cleanedName to do shell script "echo " & quoted form of notebookName & " | tr -dc '[:alnum:]' | tr '[:upper:]' '[:lower:]'"

				set backupFile to exportPath & cleanedName & ".enex"

				--display dialog notebookName & ": " & (count of matches)

				-- If there were notes that matched the filter...
				if (count of matches) > 0 then
					-- Backup the notes
					export matches to backupFile
					delay 1
					-- Compress the notes
					do shell script "/usr/bin/gzip -f " & quoted form of POSIX path of backupFile

				end if

			end repeat

		end tell

	end timeout

	-- compress the output directory and send it off to cold storage
	do shell script "tar -zcvf " & zipname & " " & quoted form of POSIX path of exportPath
	-- clean up
	do shell script "rm -rf " & quoted form of POSIX path of exportPath
end run

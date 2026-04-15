# EvernoteReadOnlyTags

Homebrew utility written in C# to set "read-only" behavior (via contentClass) on Evernote notes, via "ReadOnly" (or other user-defined) tag. 

Currently uses auth tokens because the full OAuth path is broken in the Evernote C# SDK.


How to use: 


1. Get an auth token and URL from Evernote and update the app.config. (See app.config for URL to request token.) You'll probably want to change the contentClass value too.


1. In Evernote, mark any notes you want to protect with a tag of "ReadOnly" (or whatever else you specify in the app.config).


1. Run this app. Use the -i (interactive) switch to get basic output. (You might set it up as a Scheduled Task to run periodically as well.)

To unset read-only:


1.  Run this app with the -i switch. Enter "Y" to any read-only notes you wish to unprotect.


using System;
using System.Collections.Generic;

using EvernoteSDK;
using EvernoteSDK.Advanced;
using Evernote.EDAM.Type;

namespace EvernoteReadOnlyTags
{
    class SampleData
    {
        public static void CreateSampleNote(bool readOnly, string tag)
        {
            EvernoteConnection.Create();

            ENNote sampleNote = new ENNote();
            if (readOnly)
            {
                List<string> tags = new List<string>();
                tags.Add(tag);
                sampleNote.TagNames = tags;
                sampleNote.Title = "My read-only note";
            }
            else
            {
                sampleNote.Title = "My writeable note";
            }

            sampleNote.Content = ENNoteContent.NoteContentWithString("Hello, world! " + DateTime.Now);
            ENNoteRef noteRef = EvernoteConnection.CurrentSession.UploadNote(sampleNote, null);
        }
    }
}
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using EvernoteSDK;
using EvernoteSDK.Advanced;
using Evernote.EDAM.Type;

namespace EvernoteReadOnlyTags
{
    class EvernoteConnection
    {
        private static ENSession session;

        public static void Create()
        {
            string authToken = System.Configuration.ConfigurationManager.AppSettings["authToken"];
            EvernoteReadOnlyTagsException.Assert(!string.IsNullOrEmpty(authToken), "No auth token configured.");

            string url = System.Configuration.ConfigurationManager.AppSettings["URL"];
            EvernoteReadOnlyTagsException.Assert(!string.IsNullOrEmpty(url), "No URL configured.");

            ENSessionAdvanced.SetSharedSessionDeveloperToken(authToken, url);
            if (ENSession.SharedSession.IsAuthenticated == false)
            {
                ENSession.SharedSession.AuthenticateToEvernote();
            }

            // BUG: this will always be true in the current Evernote SDK :(
            EvernoteReadOnlyTagsException.Assert(ENSession.SharedSession.IsAuthenticated, "Authentication failed");
 
            session = ENSession.SharedSession;
       }

        public static ENSession CurrentSession
        {
            get
            {
                EvernoteReadOnlyTagsException.Assert(ENSession.SharedSession.IsAuthenticated, "Not connected");
                return session;
            }
        }
    }
}
